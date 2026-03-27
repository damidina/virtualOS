import { startTransition, useEffect, useRef, useState } from "react";
import { controllerRpc } from "./rpc";
import type {
	CaptureSource,
	RemoteHealthResponse,
	RemoteJsonResponse,
	RepoStatusEntry,
	SystemStatusResponse,
} from "../shared/rpc";

const STORAGE_KEY = "virtualos-controller.config";
const DEFAULT_BASE_URL = "http://127.0.0.1:8899";
const DEFAULT_APP = "Codex";
const DEFAULT_INTERVAL_MS = 900;
const MAX_ACTIVITY_ITEMS = 14;

type SavedConfig = {
	baseUrl: string;
	appName: string;
	source: CaptureSource;
	intervalMs: number;
};

type HealthState =
	| { status: "checking"; data: null; error: string | null }
	| { status: "online"; data: RemoteHealthResponse; error: null }
	| { status: "offline"; data: null; error: string };

type SystemState =
	| { status: "loading"; data: null; error: string | null }
	| { status: "ready"; data: SystemStatusResponse; error: null }
	| { status: "error"; data: null; error: string };

function readSavedConfig(): SavedConfig {
	try {
		const raw = window.localStorage.getItem(STORAGE_KEY);
		if (!raw) {
			return {
				baseUrl: DEFAULT_BASE_URL,
				appName: DEFAULT_APP,
				source: "window",
				intervalMs: DEFAULT_INTERVAL_MS,
			};
		}

		const parsed = JSON.parse(raw) as Partial<SavedConfig>;
		return {
			baseUrl: parsed.baseUrl || DEFAULT_BASE_URL,
			appName: parsed.appName || DEFAULT_APP,
			source: parsed.source === "screen" ? "screen" : "window",
			intervalMs:
				typeof parsed.intervalMs === "number" && parsed.intervalMs >= 250
					? parsed.intervalMs
					: DEFAULT_INTERVAL_MS,
		};
	} catch {
		return {
			baseUrl: DEFAULT_BASE_URL,
			appName: DEFAULT_APP,
			source: "window",
			intervalMs: DEFAULT_INTERVAL_MS,
		};
	}
}

function normalizeBaseUrl(baseUrl: string): string {
	return baseUrl.trim().replace(/\/+$/, "");
}

function buildFrameUrl(
	baseUrl: string,
	appName: string,
	source: CaptureSource,
	frameNonce: number,
): string {
	const normalized = normalizeBaseUrl(baseUrl);
	if (!normalized) {
		return "data:,";
	}

	try {
		const root = `${normalized}/`;
		const url = new URL("frame.jpg", root);
		url.searchParams.set("ts", String(frameNonce));
		url.searchParams.set("source", source);
		if (appName.trim()) {
			url.searchParams.set("app", appName.trim());
		}
		url.searchParams.set("max", "1600");
		return url.toString();
	} catch {
		return "data:,";
	}
}

function timestampLabel(): string {
	return new Date().toLocaleTimeString([], {
		hour: "2-digit",
		minute: "2-digit",
		second: "2-digit",
	});
}

function summarizeResponse(response: RemoteJsonResponse): string {
	if (response.data && typeof response.data === "object") {
		return JSON.stringify(response.data);
	}

	if (response.text) {
		return response.text.slice(0, 120);
	}

	return response.ok ? "ok" : "no body";
}

function repoSummary(repo: RepoStatusEntry): string {
	if (!repo.exists) {
		return "missing";
	}
	if (!repo.ok) {
		return repo.error || "error";
	}
	if (repo.behind > 0) {
		return `behind ${repo.behind}`;
	}
	if (repo.dirty) {
		return "dirty";
	}
	if (repo.ahead > 0) {
		return `ahead ${repo.ahead}`;
	}
	return "up-to-date";
}

function App() {
	const initialConfig = readSavedConfig();
	const [baseUrl, setBaseUrl] = useState(initialConfig.baseUrl);
	const [appName, setAppName] = useState(initialConfig.appName);
	const [openTarget, setOpenTarget] = useState("");
	const [source, setSource] = useState<CaptureSource>(initialConfig.source);
	const [intervalMs, setIntervalMs] = useState(initialConfig.intervalMs);
	const [draftText, setDraftText] = useState("");
	const [frameNonce, setFrameNonce] = useState(0);
	const [frameStatus, setFrameStatus] = useState("idle");
	const [frameLatency, setFrameLatency] = useState<number | null>(null);
	const [frameSeenAt, setFrameSeenAt] = useState<string>("never");
	const [isLive, setIsLive] = useState(true);
	const [busyAction, setBusyAction] = useState<string | null>(null);
	const [activity, setActivity] = useState<string[]>([]);
	const [healthState, setHealthState] = useState<HealthState>({
		status: "checking",
		data: null,
		error: null,
	});
	const [systemState, setSystemState] = useState<SystemState>({
		status: "loading",
		data: null,
		error: null,
	});
	const requestedAtRef = useRef(0);
	const frameUrl = buildFrameUrl(baseUrl, appName, source, frameNonce);

	const allowedApps =
		healthState.status === "online" ? healthState.data.allowedApps : [];
	const repoStatuses =
		systemState.status === "ready" ? systemState.data.repos : [];

	useEffect(() => {
		const payload: SavedConfig = {
			baseUrl: normalizeBaseUrl(baseUrl) || DEFAULT_BASE_URL,
			appName,
			source,
			intervalMs,
		};
		window.localStorage.setItem(STORAGE_KEY, JSON.stringify(payload));
	}, [appName, baseUrl, intervalMs, source]);

	function addActivityEntry(entry: string) {
		const line = `${timestampLabel()}  ${entry}`;
		startTransition(() => {
			setActivity((current) => [line, ...current].slice(0, MAX_ACTIVITY_ITEMS));
		});
	}

	function requestFrame() {
		requestedAtRef.current = performance.now();
		setFrameStatus("requesting");
		setFrameNonce((current) => current + 1);
	}

	async function refreshHealth() {
		const targetBaseUrl = normalizeBaseUrl(baseUrl);
		if (!targetBaseUrl) {
			setHealthState({
				status: "offline",
				data: null,
				error: "enter a host first",
			});
			return;
		}

		setHealthState({ status: "checking", data: null, error: null });

		try {
			const data = await controllerRpc.request.health({ baseUrl: targetBaseUrl });
			setHealthState({
				status: "online",
				data,
				error: null,
			});
		} catch (error) {
			const message =
				error instanceof Error ? error.message : "unable to reach host";
			setHealthState({
				status: "offline",
				data: null,
				error: message,
			});
			addActivityEntry(`health failed: ${message}`);
		}
	}

	useEffect(() => {
		refreshHealth();
		const timer = window.setInterval(() => {
			void refreshHealth();
		}, 6000);
		return () => window.clearInterval(timer);
	}, [baseUrl]);

	async function refreshSystemStatus() {
		const targetBaseUrl = normalizeBaseUrl(baseUrl);
		if (!targetBaseUrl) {
			setSystemState({
				status: "error",
				data: null,
				error: "enter a host first",
			});
			return;
		}

		setSystemState({ status: "loading", data: null, error: null });

		try {
			const response = await controllerRpc.request.getJson({
				baseUrl: targetBaseUrl,
				path: "/api/system/status",
			});
			if (!response.ok || !response.data || typeof response.data !== "object") {
				throw new Error(`system status failed with ${response.status}`);
			}
			setSystemState({
				status: "ready",
				data: response.data as SystemStatusResponse,
				error: null,
			});
		} catch (error) {
			const message =
				error instanceof Error ? error.message : "system status failed";
			setSystemState({
				status: "error",
				data: null,
				error: message,
			});
		}
	}

	useEffect(() => {
		void refreshSystemStatus();
		const timer = window.setInterval(() => {
			void refreshSystemStatus();
		}, 15000);
		return () => window.clearInterval(timer);
	}, [baseUrl]);

	useEffect(() => {
		requestFrame();
		if (!isLive) {
			return undefined;
		}

		const timer = window.setInterval(() => {
			requestFrame();
		}, Math.max(250, intervalMs));
		return () => window.clearInterval(timer);
	}, [appName, baseUrl, intervalMs, isLive, source]);

	async function runControlAction(
		label: string,
		path: string,
		payload: Record<string, unknown>,
	) {
		const targetBaseUrl = normalizeBaseUrl(baseUrl);
		if (!targetBaseUrl) {
			addActivityEntry(`${label}: missing host`);
			return;
		}

		setBusyAction(label);
		try {
			const response = await controllerRpc.request.control({
				baseUrl: targetBaseUrl,
				path,
				payload,
			});
			addActivityEntry(
				`${label}: ${response.status} ${summarizeResponse(response)}`,
			);
			if (response.ok) {
				requestFrame();
			}
		} catch (error) {
			const message =
				error instanceof Error ? error.message : "request failed";
			addActivityEntry(`${label}: ${message}`);
		} finally {
			setBusyAction(null);
		}
	}

	async function pullRepo(repo: RepoStatusEntry) {
		const targetBaseUrl = normalizeBaseUrl(baseUrl);
		if (!targetBaseUrl) {
			addActivityEntry(`pull ${repo.name}: missing host`);
			return;
		}

		setBusyAction(`pull ${repo.name}`);
		try {
			const response = await controllerRpc.request.control({
				baseUrl: targetBaseUrl,
				path: "/api/system/pull",
				payload: { repo: repo.path },
			});
			addActivityEntry(
				`pull ${repo.name}: ${response.status} ${summarizeResponse(response)}`,
			);
			await refreshSystemStatus();
		} catch (error) {
			const message =
				error instanceof Error ? error.message : "pull failed";
			addActivityEntry(`pull ${repo.name}: ${message}`);
		} finally {
			setBusyAction(null);
		}
	}

	function focusSelectedApp(nextApp?: string) {
		const value = (nextApp ?? appName).trim();
		if (!value) {
			addActivityEntry("focus skipped: no app selected");
			return;
		}

		if (nextApp) {
			setAppName(nextApp);
		}

		void runControlAction(`focus ${value}`, "/control/focus", { app: value });
	}

	function typeDraft(withEnter: boolean) {
		if (!draftText.trim()) {
			addActivityEntry("type skipped: no text");
			return;
		}

		void (async () => {
			await runControlAction("type text", "/control/type", { text: draftText });
			if (withEnter) {
				await runControlAction("press enter", "/control/key", {
					key: "enter",
				});
			}
		})();
	}

	function openTargetValue(nextTarget?: string) {
		const target = (nextTarget ?? openTarget).trim();
		if (!target) {
			addActivityEntry("open skipped: target is empty");
			return;
		}

		const payload = /^https?:\/\//i.test(target)
			? { url: target }
			: target.startsWith("/") || target.startsWith("~")
				? { path: target }
				: { app: target };

		if (!nextTarget) {
			setOpenTarget(target);
		}

		void runControlAction(`open ${target}`, "/control/open", payload);
	}

	function clickFrame(event: React.MouseEvent<HTMLButtonElement>) {
		const rect = event.currentTarget.getBoundingClientRect();
		if (rect.width <= 0 || rect.height <= 0) {
			return;
		}

		const nx = (event.clientX - rect.left) / rect.width;
		const ny = (event.clientY - rect.top) / rect.height;
		const payload: Record<string, unknown> = {
			nx,
			ny,
			source,
		};

		if (appName.trim()) {
			payload.app = appName.trim();
		}

		void runControlAction("click frame", "/control/click", payload);
	}

	return (
		<div className="min-h-screen bg-ink text-paper">
			<div className="pointer-events-none absolute inset-0 overflow-hidden">
				<div className="orb orb-amber" />
				<div className="orb orb-cyan" />
				<div className="grid-mask" />
			</div>

			<div className="relative mx-auto flex min-h-screen max-w-[1600px] flex-col gap-6 px-6 py-6">
				<header className="panel flex items-start justify-between gap-6 px-6 py-5">
					<div>
						<p className="eyebrow">Electrobun Controller</p>
						<h1 className="headline">virtualOS Control Room</h1>
						<p className="subhead">
							Direct desktop control over the live LAN host without using the
							browser debug page.
						</p>
					</div>
					<div className="status-stack">
						<div
							className={`status-pill ${
								healthState.status === "online"
									? "status-pill-online"
									: healthState.status === "checking"
										? "status-pill-checking"
										: "status-pill-offline"
							}`}
						>
							<span className="status-dot" />
							<span>
								{healthState.status === "online"
									? "connected"
									: healthState.status === "checking"
										? "checking"
										: "offline"}
							</span>
						</div>
						<div className="mono text-xs text-paper/70">{frameSeenAt}</div>
					</div>
				</header>

				<div className="grid flex-1 gap-6 xl:grid-cols-[320px_minmax(0,1fr)_360px]">
					<section className="panel flex flex-col gap-5 p-5">
						<div>
							<p className="section-label">Connection</p>
							<div className="space-y-3">
								<label className="field">
									<span>Host endpoint</span>
									<input
										value={baseUrl}
										onChange={(event) => setBaseUrl(event.target.value)}
										placeholder="http://192.168.2.196:8899"
									/>
								</label>
								<div className="grid grid-cols-[1fr_140px] gap-3">
									<label className="field">
										<span>Target app</span>
										<input
											value={appName}
											onChange={(event) => setAppName(event.target.value)}
											placeholder="Codex"
										/>
									</label>
									<label className="field">
										<span>Capture</span>
										<select
											value={source}
											onChange={(event) =>
												setSource(event.target.value as CaptureSource)
											}
										>
											<option value="window">window</option>
											<option value="screen">screen</option>
										</select>
									</label>
								</div>
								<label className="field">
									<span>Refresh cadence</span>
									<div className="inline-field">
										<input
											type="number"
											min={250}
											step={50}
											value={intervalMs}
											onChange={(event) =>
												setIntervalMs(
													Math.max(
														250,
														Number(event.target.value || DEFAULT_INTERVAL_MS),
													),
												)
											}
										/>
										<span className="suffix">ms</span>
									</div>
								</label>
							</div>
						</div>

						<div className="button-row">
							<button className="button-primary" onClick={() => void refreshHealth()}>
								Ping host
							</button>
							<button className="button-secondary" onClick={requestFrame}>
								Single frame
							</button>
							<button
								className="button-secondary"
								onClick={() => setIsLive((value) => !value)}
							>
								{isLive ? "Pause live" : "Resume live"}
							</button>
						</div>

						<div className="detail-card">
							<p className="section-label">Host summary</p>
							<div className="metric-grid">
								<div>
									<span className="metric-label">Frame</span>
									<strong>{frameStatus}</strong>
								</div>
								<div>
									<span className="metric-label">Latency</span>
									<strong>{frameLatency ? `${frameLatency} ms` : "--"}</strong>
								</div>
								<div>
									<span className="metric-label">Auth</span>
									<strong>
										{healthState.status === "online" &&
										healthState.data.authRequired
											? "required"
											: "open"}
									</strong>
								</div>
								<div>
									<span className="metric-label">Apps</span>
									<strong>{allowedApps.length || "--"}</strong>
								</div>
							</div>
							{healthState.status === "offline" ? (
								<p className="text-sm text-rose-300">{healthState.error}</p>
							) : null}
						</div>

						<div className="detail-card">
							<p className="section-label">Quick focus</p>
							<div className="chip-cloud">
								{allowedApps.length ? (
									allowedApps.map((allowedApp) => (
										<button
											key={allowedApp}
											className={`chip ${
												allowedApp === appName ? "chip-active" : ""
											}`}
											onClick={() => focusSelectedApp(allowedApp)}
										>
											{allowedApp}
										</button>
									))
								) : (
									<p className="text-sm text-paper/60">
										Ping the host to load the allowlist.
									</p>
								)}
							</div>
						</div>

						<div className="detail-card">
							<p className="section-label">Repo updates</p>
							<div className="space-y-2">
								{repoStatuses.length ? (
									repoStatuses.map((repo) => (
										<div
											key={repo.path}
											className="flex items-center justify-between gap-3 text-sm"
										>
											<div className="min-w-0">
												<div>{repo.name}</div>
												<div className="mono text-xs text-paper/45">
													{repo.branch || "detached"} {repo.headShort || ""}
												</div>
											</div>
											<div className="flex items-center gap-2">
												<div
													className={`repo-badge ${
														repo.updateAvailable
															? "repo-badge-warn"
															: repo.ok
																? "repo-badge-ok"
																: "repo-badge-bad"
													}`}
												>
													{repoSummary(repo)}
												</div>
												<button
													className="button-secondary px-3 py-2 text-xs"
													onClick={() => void pullRepo(repo)}
													disabled={!repo.ok || repo.dirty}
												>
													Pull
												</button>
											</div>
										</div>
									))
								) : (
									<p className="text-sm text-paper/60">
										{systemState.status === "error"
											? systemState.error
											: "No watched repos yet."}
									</p>
								)}
							</div>
							<div className="mt-3">
								<button
									className="button-secondary"
									onClick={() => void refreshSystemStatus()}
								>
									Refresh repo status
								</button>
							</div>
						</div>
					</section>

					<section className="panel flex min-h-[720px] flex-col gap-4 p-4">
						<div className="flex items-center justify-between gap-4 px-2">
							<div>
								<p className="section-label">Live frame</p>
								<p className="text-sm text-paper/65">
									Click directly on the frame to send normalized remote clicks.
								</p>
							</div>
							<div className="mono text-xs text-paper/60">{frameUrl}</div>
						</div>

						<button className="frame-shell" onClick={clickFrame}>
							<img
								key={frameUrl}
								src={frameUrl}
								alt="Remote desktop frame"
								className="frame-image"
								onLoad={() => {
									setFrameStatus("live");
									setFrameSeenAt(timestampLabel());
									setFrameLatency(
										Math.round(performance.now() - requestedAtRef.current),
									);
								}}
								onError={() => {
									setFrameStatus("error");
									setFrameLatency(null);
								}}
							/>
							<div className="frame-overlay">
								<span>{healthState.status === "online" ? "LAN link ready" : "waiting for host"}</span>
								<span>{busyAction ? `action: ${busyAction}` : "click to interact"}</span>
							</div>
						</button>
					</section>

					<section className="panel flex flex-col gap-5 p-5">
						<div>
							<p className="section-label">Actions</p>
							<div className="button-grid">
								<button
									className="button-primary"
									onClick={() => focusSelectedApp()}
								>
									Focus app
								</button>
								<button
									className="button-secondary"
									onClick={() =>
										void runControlAction("click center", "/control/click", {
											nx: 0.5,
											ny: 0.5,
											source,
											app: appName.trim() || undefined,
										})
									}
								>
									Click center
								</button>
								<button
									className="button-secondary"
									onClick={() =>
										void runControlAction("press enter", "/control/key", {
											key: "enter",
										})
									}
								>
									Enter
								</button>
								<button
									className="button-secondary"
									onClick={() =>
										void runControlAction("press escape", "/control/key", {
											key: "escape",
										})
									}
								>
									Escape
								</button>
								<button
									className="button-secondary"
									onClick={() =>
										void runControlAction("paste shortcut", "/control/shortcut", {
											key: "v",
											modifiers: ["command"],
										})
									}
								>
									Command+V
								</button>
							</div>
						</div>

						<div className="detail-card">
							<p className="section-label">Open</p>
							<input
								value={openTarget}
								onChange={(event) => setOpenTarget(event.target.value)}
								placeholder="App, https:// URL, or /absolute/path"
								className="w-full rounded-2xl border border-white/10 bg-black/20 px-4 py-3 text-sm text-paper outline-none"
							/>
							<div className="button-row mt-3">
								<button className="button-primary" onClick={() => openTargetValue()}>
									Open target
								</button>
								<button
									className="button-secondary"
									onClick={() => openTargetValue(appName)}
								>
									Open app
								</button>
							</div>
						</div>

						<div className="detail-card">
							<p className="section-label">Type</p>
							<textarea
								value={draftText}
								onChange={(event) => setDraftText(event.target.value)}
								placeholder="Send text into the focused app"
								className="composer"
							/>
							<div className="button-row">
								<button className="button-primary" onClick={() => typeDraft(false)}>
									Type text
								</button>
								<button
									className="button-secondary"
									onClick={() => typeDraft(true)}
								>
									Type + Enter
								</button>
							</div>
						</div>

						<div className="detail-card grow">
							<p className="section-label">Activity</p>
							<div className="activity-feed">
								{activity.length ? (
									activity.map((entry) => (
										<div key={entry} className="activity-line">
											{entry}
										</div>
									))
								) : (
									<div className="activity-line text-paper/50">
										Control events will appear here.
									</div>
								)}
							</div>
						</div>
					</section>
				</div>
			</div>
		</div>
	);
}

export default App;
