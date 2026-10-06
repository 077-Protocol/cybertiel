// Trusted local Pi extension: enforce a finite deadline on every model-issued bash call.
// The file is root-owned/read-only inside the container and loaded explicitly while
// extension auto-discovery remains disabled.
const MAX_TIMEOUT_SECONDS = 7200;

export default function (pi) {
  pi.on("tool_call", (event) => {
    if (event.toolName !== "bash") return;
    const input = event.input;
    if (!input || typeof input !== "object") return;
    const raw = input.timeout;
    if (typeof raw !== "number" || !Number.isFinite(raw) || raw <= 0) {
      input.timeout = MAX_TIMEOUT_SECONDS;
      return;
    }
    input.timeout = Math.min(Math.max(Math.trunc(raw), 1), MAX_TIMEOUT_SECONDS);
  });
}
