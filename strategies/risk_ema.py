from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

from nautilus_trader.config import PositiveFloat
from nautilus_trader.config import PositiveInt
from nautilus_trader.config import StrategyConfig
from nautilus_trader.core.correctness import PyCondition
from nautilus_trader.indicators import ExponentialMovingAverage
from nautilus_trader.model.data import Bar
from nautilus_trader.model.data import BarType
from nautilus_trader.model.enums import OrderSide
from nautilus_trader.model.enums import TimeInForce
from nautilus_trader.model.events import PositionClosed
from nautilus_trader.model.identifiers import ClientId
from nautilus_trader.model.identifiers import InstrumentId
from nautilus_trader.model.instruments import Instrument
from nautilus_trader.model.objects import Quantity
from nautilus_trader.model.orders import MarketOrder
from nautilus_trader.model.position import Position
from nautilus_trader.trading.strategy import Strategy


class RiskManagedEMAStrategyConfig(StrategyConfig, frozen=True):
    instrument_id: InstrumentId
    bar_type: BarType
    capital_usdt: PositiveFloat
    risk_per_trade_pct: PositiveFloat = 0.005
    stop_loss_pct: PositiveFloat = 0.012
    take_profit_pct: PositiveFloat = 0.024
    daily_loss_limit_pct: PositiveFloat = 0.03
    fast_ema_period: PositiveInt = 9
    slow_ema_period: PositiveInt = 21
    request_bars_lookback_hours: PositiveInt = 24
    allow_short: bool = False
    leverage_cap: PositiveInt = 1
    client_id: ClientId | None = None
    close_positions_on_stop: bool = True
    reduce_only_on_exit: bool = True


class RiskManagedEMAStrategy(Strategy):
    """
    EMA trend-following strategy with basic risk controls.

    Entry:
    - Go long when fast EMA >= slow EMA.
    - Go short when fast EMA < slow EMA and `allow_short=True`.

    Exit:
    - Fixed stop-loss / take-profit from position average open price.
    - Signal reversal.
    - Daily realized-loss guard.
    """

    def __init__(self, config: RiskManagedEMAStrategyConfig) -> None:
        PyCondition.is_true(
            config.fast_ema_period < config.slow_ema_period,
            "{config.fast_ema_period=} must be less than {config.slow_ema_period=}",
        )
        super().__init__(config)

        self.instrument: Instrument | None = None
        self.fast_ema = ExponentialMovingAverage(config.fast_ema_period)
        self.slow_ema = ExponentialMovingAverage(config.slow_ema_period)

        self._daily_loss_usdt = 0.0
        self._daily_loss_day = None

    def on_start(self) -> None:
        self.instrument = self.cache.instrument(self.config.instrument_id)
        if self.instrument is None:
            self.log.error(f"Could not find instrument for {self.config.instrument_id}")
            self.stop()
            return

        self.register_indicator_for_bars(self.config.bar_type, self.fast_ema)
        self.register_indicator_for_bars(self.config.bar_type, self.slow_ema)

        self.request_bars(
            self.config.bar_type,
            client_id=self.config.client_id,
            start=self.clock.utc_now() - timedelta(hours=self.config.request_bars_lookback_hours),
        )
        self.subscribe_bars(self.config.bar_type, client_id=self.config.client_id)

    def on_bar(self, bar: Bar) -> None:
        self._roll_daily_window()

        if not self.indicators_initialized():
            return
        if bar.is_single_price():
            return

        market_price = float(bar.close)
        bullish = self.fast_ema.value >= self.slow_ema.value
        position = self._current_position()

        if position is not None:
            if self._should_exit_for_risk(position, market_price):
                self._exit_all_positions("risk exit")
                return
            if self._should_exit_for_signal(position, bullish):
                self._exit_all_positions("signal reversal")
                return
            return

        if self._is_daily_loss_limit_hit():
            return
        if self._has_pending_orders():
            return

        if bullish:
            self._submit_entry(OrderSide.BUY, market_price)
        elif self.config.allow_short:
            self._submit_entry(OrderSide.SELL, market_price)

    def on_position_closed(self, event: PositionClosed) -> None:
        if event.instrument_id != self.config.instrument_id:
            return
        self._roll_daily_window()
        realized_pnl = float(event.realized_pnl)
        if realized_pnl < 0:
            self._daily_loss_usdt += abs(realized_pnl)
            self.log.warning(
                f"[{self.id}] daily realized loss={self._daily_loss_usdt:.4f} USDT "
                f"(limit={self._daily_loss_limit_usdt():.4f} USDT)",
            )

    def on_stop(self) -> None:
        self.cancel_all_orders(self.config.instrument_id, client_id=self.config.client_id)
        if self.config.close_positions_on_stop:
            self._exit_all_positions("strategy stop")
        self.unsubscribe_bars(self.config.bar_type, client_id=self.config.client_id)

    def on_reset(self) -> None:
        self.fast_ema.reset()
        self.slow_ema.reset()
        self._daily_loss_usdt = 0.0
        self._daily_loss_day = None

    def _submit_entry(self, order_side: OrderSide, market_price: float) -> None:
        if self.instrument is None:
            return

        qty = self._calc_order_qty(market_price)
        if qty is None:
            self.log.warning(f"[{self.id}] order qty resolved to 0, skip entry")
            return

        order: MarketOrder = self.order_factory.market(
            instrument_id=self.config.instrument_id,
            order_side=order_side,
            quantity=qty,
            time_in_force=TimeInForce.GTC,
        )
        self.submit_order(order, client_id=self.config.client_id)

    def _calc_order_qty(self, market_price: float) -> Quantity | None:
        if self.instrument is None:
            return None
        if market_price <= 0:
            return None

        risk_budget_usdt = self.config.capital_usdt * self.config.risk_per_trade_pct
        stop_distance = market_price * self.config.stop_loss_pct
        if stop_distance <= 0:
            return None

        qty_by_risk = risk_budget_usdt / stop_distance
        max_notional = self.config.capital_usdt * self.config.leverage_cap
        qty_by_notional = max_notional / market_price
        raw_qty = min(qty_by_risk, qty_by_notional)

        if raw_qty <= 0:
            return None

        try:
            qty = self.instrument.make_qty(Decimal(f"{raw_qty:.10f}"))
        except Exception:
            return None

        if float(qty) <= 0:
            return None
        return qty

    def _current_position(self) -> Position | None:
        positions = self.cache.positions_open(
            instrument_id=self.config.instrument_id,
            strategy_id=self.id,
        )
        return positions[0] if positions else None

    def _has_pending_orders(self) -> bool:
        open_orders = self.cache.orders_open(
            instrument_id=self.config.instrument_id,
            strategy_id=self.id,
        )
        inflight_orders = self.cache.orders_inflight(
            instrument_id=self.config.instrument_id,
            strategy_id=self.id,
        )
        return bool(open_orders or inflight_orders)

    def _should_exit_for_risk(self, position: Position, market_price: float) -> bool:
        entry_px = float(position.avg_px_open)
        if entry_px <= 0:
            return False

        if position.signed_qty > 0:
            stop_price = entry_px * (1.0 - self.config.stop_loss_pct)
            take_price = entry_px * (1.0 + self.config.take_profit_pct)
            return market_price <= stop_price or market_price >= take_price

        stop_price = entry_px * (1.0 + self.config.stop_loss_pct)
        take_price = entry_px * (1.0 - self.config.take_profit_pct)
        return market_price >= stop_price or market_price <= take_price

    def _should_exit_for_signal(self, position: Position, bullish_signal: bool) -> bool:
        if position.signed_qty > 0 and not bullish_signal:
            return True
        if position.signed_qty < 0 and bullish_signal:
            return True
        return False

    def _exit_all_positions(self, reason: str) -> None:
        self.log.info(f"[{self.id}] {reason}, closing position(s)")
        self.close_all_positions(
            instrument_id=self.config.instrument_id,
            client_id=self.config.client_id,
            reduce_only=self.config.reduce_only_on_exit,
        )

    def _roll_daily_window(self) -> None:
        current_day = self.clock.utc_now().date()
        if self._daily_loss_day is None:
            self._daily_loss_day = current_day
            return
        if current_day != self._daily_loss_day:
            self._daily_loss_day = current_day
            self._daily_loss_usdt = 0.0

    def _daily_loss_limit_usdt(self) -> float:
        return self.config.capital_usdt * self.config.daily_loss_limit_pct

    def _is_daily_loss_limit_hit(self) -> bool:
        return self._daily_loss_usdt >= self._daily_loss_limit_usdt()

