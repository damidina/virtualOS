import { BrowserView, BrowserWindow, Updater } from "electrobun/bun";
import type {
	ControllerRPC,
	RemoteControlRequest,
	RemoteHealthResponse,
	RemoteJsonResponse,
} from "../shared/rpc";

const DEV_SERVER_PORT = 5173;
const DEV_SERVER_URL = `http://localhost:${DEV_SERVER_PORT}`;
const REMOTE_TIMEOUT_MS = 5000;

// Check if Vite dev server is running for HMR
async function getMainViewUrl(): Promise<string> {
	const channel = await Updater.localInfo.channel();
	if (channel === "dev") {
		try {
			await fetch(DEV_SERVER_URL, { method: "HEAD" });
			console.log(`HMR enabled: Using Vite dev server at ${DEV_SERVER_URL}`);
			return DEV_SERVER_URL;
		} catch {
			console.log(
				"Vite dev server not running. Run 'bun run dev:hmr' for HMR support.",
			);
		}
	}
	return "views://mainview/index.html";
}

function normalizeBaseUrl(baseUrl: string): string {
	return baseUrl.trim().replace(/\/+$/, "");
}

function buildRemoteUrl(baseUrl: string, path: string): string {
	const root = `${normalizeBaseUrl(baseUrl)}/`;
	return new URL(path.replace(/^\//, ""), root).toString();
}

async function requestRemoteJson(
	baseUrl: string,
	path: string,
	init: RequestInit = {},
): Promise<RemoteJsonResponse> {
	const controller = new AbortController();
	const timeout = setTimeout(() => controller.abort(), REMOTE_TIMEOUT_MS);
	const url = buildRemoteUrl(baseUrl, path);

	try {
		const response = await fetch(url, {
			...init,
			signal: controller.signal,
			headers: {
				accept: "application/json",
				...(init.headers ?? {}),
			},
		});
		const text = await response.text();
		let data: unknown = null;

		if (text) {
			try {
				data = JSON.parse(text);
			} catch {
				data = null;
			}
		}

		return {
			ok: response.ok,
			status: response.status,
			url,
			text,
			data,
		};
	} finally {
		clearTimeout(timeout);
	}
}

function asHealthResponse(response: RemoteJsonResponse): RemoteHealthResponse {
	if (!response.ok) {
		throw new Error(`health failed with ${response.status}`);
	}

	if (!response.data || typeof response.data !== "object") {
		throw new Error("health returned a non-JSON payload");
	}

	return response.data as RemoteHealthResponse;
}

const controllerRpc = BrowserView.defineRPC<ControllerRPC>({
	maxRequestTime: REMOTE_TIMEOUT_MS + 1000,
	handlers: {
		requests: {
			health: async ({ baseUrl }) => {
				const response = await requestRemoteJson(baseUrl, "/health");
				return asHealthResponse(response);
			},
			control: async ({ baseUrl, path, payload }: RemoteControlRequest) =>
				requestRemoteJson(baseUrl, path, {
					method: "POST",
					headers: {
						"content-type": "application/json",
					},
					body: JSON.stringify(payload ?? {}),
				}),
		},
		messages: {},
	},
});

// Create the main application window
const url = await getMainViewUrl();

new BrowserWindow({
	title: "virtualOS Controller",
	url,
	frame: {
		width: 1480,
		height: 960,
		x: 120,
		y: 80,
	},
	rpc: controllerRpc,
});

console.log("virtualOS Controller started");
