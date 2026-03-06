from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv

from nautilus_trader.adapters.binance import BinanceAccountType
from nautilus_trader.adapters.binance import BinanceDataClientConfig
from nautilus_trader.adapters.binance import BinanceExecClientConfig
from nautilus_trader.adapters.binance import BinanceInstrumentProviderConfig
from nautilus_trader.adapters.binance import BinanceLiveDataClientFactory
from nautilus_trader.adapters.binance import BinanceLiveExecClientFactory
from nautilus_trader.adapters.binance.common.enums import BinanceEnvironment
from nautilus_trader.adapters.binance.common.symbol import BinanceSymbol
from nautilus_trader.adapters.binance.futures.enums import BinanceFuturesMarginType
from nautilus_trader.adapters.binance.futures.http.wallet import BinanceFuturesWalletHttpAPI
from nautilus_trader.adapters.binance.http.account import BinanceAccountHttpAPI
from nautilus_trader.adapters.binance.spot.http.wallet import BinanceSpotWalletHttpAPI
from nautilus_trader.adapters.binance.websocket.user import BinanceUserDataWebSocketClient
from nautilus_trader.config import InstrumentProviderConfig
from nautilus_trader.config import LiveExecEngineConfig
from nautilus_trader.config import LoggingConfig
from nautilus_trader.config import TradingNodeConfig
from nautilus_trader.live.node import TradingNode
from nautilus_trader.model.data import BarType
from nautilus_trader.model.identifiers import ClientId
from nautilus_trader.model.identifiers import InstrumentId
from nautilus_trader.model.identifiers import TraderId
from nautilus_trader.model.venues import Venue

from strategies import RiskManagedEMAStrategy
from strategies import RiskManagedEMAStrategyConfig


ROOT_DIR = Path(__file__).resolve().parent
ENV_PATH = ROOT_DIR / ".env"


def _read_env(name: str) -> str | None:
    value = os.getenv(name)
    if value is None:
        return None
    normalized = value.strip().strip('"').strip("'")
    if "\\n" in normalized and "PRIVATE KEY" in normalized:
        normalized = normalized.replace("\\n", "\n")
    return normalized or None


def _require_env(name: str, fallback: str | None = None) -> str:
    value = _read_env(name)
    if value:
        return value
    if fallback:
        fallback_value = _read_env(fallback)
        if fallback_value:
            return fallback_value
    if fallback:
        raise RuntimeError(
            f"Missing env var: {name} (fallback: {fallback}). "
            f"Create {ENV_PATH} from .env.example and fill API keys.",
        )
    raise RuntimeError(
        f"Missing env var: {name}. "
        f"Create {ENV_PATH} from .env.example and fill API keys.",
    )


def _read_float(name: str, default: float) -> float:
    value = _read_env(name)
    return float(value) if value else default


def _read_int(name: str, default: int) -> int:
    value = _read_env(name)
    return int(value) if value else default


def _apply_timestamp_offset(offset_ms: int) -> None:
    if offset_ms == 0:
        return

    def _patched_timestamp(self) -> str:
        return str(self._clock.timestamp_ms() + offset_ms)

    # Patch Binance signed HTTP request timestamps for account/wallet endpoints.
    BinanceAccountHttpAPI._timestamp = _patched_timestamp
    BinanceSpotWalletHttpAPI._timestamp = _patched_timestamp
    BinanceFuturesWalletHttpAPI._timestamp = _patched_timestamp

    async def _patched_session_logon(self):
        if self._use_rest_listen_key:
            self._is_authenticated = True
            self._log.info("Session authenticated (REST listenKey mode)")
            return {}

        timestamp = self._clock.timestamp_ms() + offset_ms
        sign_params = f"apiKey={self._api_key}&timestamp={timestamp}"
        signature = self._get_sign(sign_params)

        response = await self._send_request(
            "session.logon",
            {"apiKey": self._api_key, "timestamp": timestamp, "signature": signature},
        )
        self._is_authenticated = True
        self._log.info("Session authenticated")
        return response

    BinanceUserDataWebSocketClient.session_logon = _patched_session_logon


def _apply_user_ws_keepalive_interval(interval_secs: int) -> None:
    if interval_secs <= 0:
        return
    BinanceUserDataWebSocketClient._KEEPALIVE_INTERVAL_SECS = interval_secs


load_dotenv(dotenv_path=ENV_PATH, override=False)
binance_timestamp_offset_ms = _read_int("BINANCE_TIMESTAMP_OFFSET_MS", 0)
_apply_timestamp_offset(binance_timestamp_offset_ms)
binance_user_ws_keepalive_secs = _read_int("BINANCE_USER_WS_KEEPALIVE_SECS", 1800)
_apply_user_ws_keepalive_interval(binance_user_ws_keepalive_secs)

base_symbol = (_read_env("SYMBOL") or "SOLUSDT").upper()
futures_symbol = f"{base_symbol}-PERP"
binance_proxy_url = _read_env("BINANCE_PROXY_URL")

total_capital_usdt = _read_float("TOTAL_CAPITAL_USDT", 500.0)
spot_capital_ratio = _read_float("SPOT_CAPITAL_RATIO", 0.40)
spot_capital_usdt = total_capital_usdt * spot_capital_ratio
futures_capital_usdt = total_capital_usdt - spot_capital_usdt

risk_per_trade_pct = _read_float("RISK_PER_TRADE_PCT", 0.005)
stop_loss_pct = _read_float("STOP_LOSS_PCT", 0.012)
take_profit_pct = _read_float("TAKE_PROFIT_PCT", 0.024)
daily_loss_limit_pct = _read_float("DAILY_LOSS_LIMIT_PCT", 0.03)
futures_max_leverage = _read_int("FUTURES_MAX_LEVERAGE", 50)

spot_api_key = _require_env("BINANCE_SPOT_TESTNET_API_KEY", fallback="BINANCE_TESTNET_API_KEY")
spot_api_secret = _require_env(
    "BINANCE_SPOT_TESTNET_API_SECRET",
    fallback="BINANCE_TESTNET_API_SECRET",
)
futures_api_key = _require_env(
    "BINANCE_FUTURES_TESTNET_API_KEY",
    fallback="BINANCE_TESTNET_API_KEY",
)
futures_api_secret = _require_env(
    "BINANCE_FUTURES_TESTNET_API_SECRET",
    fallback="BINANCE_TESTNET_API_SECRET",
)

spot_client_id = "BINANCE_SPOT"
futures_client_id = "BINANCE_FUTURES"

spot_instrument_id = InstrumentId.from_str(f"{base_symbol}.{spot_client_id}")
futures_instrument_id = InstrumentId.from_str(f"{futures_symbol}.{futures_client_id}")

config_node = TradingNodeConfig(
    trader_id=TraderId("SOLBOT-001"),
    logging=LoggingConfig(log_level="INFO", use_pyo3=True, log_colors=True),
    exec_engine=LiveExecEngineConfig(
        reconciliation=True,
        reconciliation_lookback_mins=60 * 24,
    ),
    data_clients={
        spot_client_id: BinanceDataClientConfig(
            venue=Venue(spot_client_id),
            api_key=spot_api_key,
            api_secret=spot_api_secret,
            proxy_url=binance_proxy_url,
            account_type=BinanceAccountType.SPOT,
            environment=BinanceEnvironment.TESTNET,
            instrument_provider=InstrumentProviderConfig(load_ids=frozenset([spot_instrument_id])),
        ),
        futures_client_id: BinanceDataClientConfig(
            venue=Venue(futures_client_id),
            api_key=futures_api_key,
            api_secret=futures_api_secret,
            proxy_url=binance_proxy_url,
            account_type=BinanceAccountType.USDT_FUTURES,
            environment=BinanceEnvironment.TESTNET,
            instrument_provider=BinanceInstrumentProviderConfig(
                load_ids=frozenset([futures_instrument_id]),
                query_commission_rates=True,
            ),
        ),
    },
    exec_clients={
        spot_client_id: BinanceExecClientConfig(
            venue=Venue(spot_client_id),
            api_key=spot_api_key,
            api_secret=spot_api_secret,
            proxy_url=binance_proxy_url,
            account_type=BinanceAccountType.SPOT,
            environment=BinanceEnvironment.TESTNET,
            instrument_provider=InstrumentProviderConfig(load_ids=frozenset([spot_instrument_id])),
            max_retries=3,
        ),
        futures_client_id: BinanceExecClientConfig(
            venue=Venue(futures_client_id),
            api_key=futures_api_key,
            api_secret=futures_api_secret,
            proxy_url=binance_proxy_url,
            account_type=BinanceAccountType.USDT_FUTURES,
            environment=BinanceEnvironment.TESTNET,
            instrument_provider=BinanceInstrumentProviderConfig(
                load_ids=frozenset([futures_instrument_id]),
                query_commission_rates=True,
            ),
            futures_leverages={BinanceSymbol(base_symbol): futures_max_leverage},
            futures_margin_types={BinanceSymbol(base_symbol): BinanceFuturesMarginType.ISOLATED},
            max_retries=3,
        ),
    },
    timeout_connection=30.0,
    timeout_reconciliation=15.0,
    timeout_portfolio=15.0,
    timeout_disconnection=10.0,
    timeout_post_stop=5.0,
)

node = TradingNode(config=config_node)

spot_strategy = RiskManagedEMAStrategy(
    RiskManagedEMAStrategyConfig(
        instrument_id=spot_instrument_id,
        external_order_claims=[spot_instrument_id],
        bar_type=BarType.from_str(f"{base_symbol}.{spot_client_id}-1-MINUTE-LAST-INTERNAL"),
        capital_usdt=spot_capital_usdt,
        risk_per_trade_pct=risk_per_trade_pct,
        stop_loss_pct=stop_loss_pct,
        take_profit_pct=take_profit_pct,
        daily_loss_limit_pct=daily_loss_limit_pct,
        allow_short=False,
        leverage_cap=1,
        client_id=ClientId(spot_client_id),
        reduce_only_on_exit=False,
    ),
)

futures_strategy = RiskManagedEMAStrategy(
    RiskManagedEMAStrategyConfig(
        instrument_id=futures_instrument_id,
        external_order_claims=[futures_instrument_id],
        bar_type=BarType.from_str(f"{futures_symbol}.{futures_client_id}-1-MINUTE-LAST-EXTERNAL"),
        capital_usdt=futures_capital_usdt,
        risk_per_trade_pct=risk_per_trade_pct,
        stop_loss_pct=stop_loss_pct,
        take_profit_pct=take_profit_pct,
        daily_loss_limit_pct=daily_loss_limit_pct,
        allow_short=True,
        leverage_cap=futures_max_leverage,
        client_id=ClientId(futures_client_id),
        reduce_only_on_exit=True,
    ),
)

node.trader.add_strategies([spot_strategy, futures_strategy])
node.add_data_client_factory(spot_client_id, BinanceLiveDataClientFactory)
node.add_exec_client_factory(spot_client_id, BinanceLiveExecClientFactory)
node.add_data_client_factory(futures_client_id, BinanceLiveDataClientFactory)
node.add_exec_client_factory(futures_client_id, BinanceLiveExecClientFactory)
node.build()


if __name__ == "__main__":
    try:
        node.run()
    finally:
        node.dispose()
