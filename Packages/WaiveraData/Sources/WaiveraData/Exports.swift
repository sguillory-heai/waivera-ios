// Connection types features read through `RealtimeStatusRepository.statuses()`, re-exported so
// feature modules need no direct dependency on the realtime transport.
@_exported import enum WaiveraRealtime.ConnectionState
@_exported import struct WaiveraRealtime.RealtimeStatus
