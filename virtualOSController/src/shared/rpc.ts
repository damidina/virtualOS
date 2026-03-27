import type { RPCSchema } from "electrobun/bun";

export type CaptureSource = "window" | "screen";

export type RemoteHealthResponse = {
	ok: boolean;
	endpoints: string[];
	allowedApps: string[];
	bonjourServiceType?: string;
	authRequired?: boolean;
};

export type RemoteJsonResponse = {
	ok: boolean;
	status: number;
	url: string;
	text: string;
	data: unknown;
};

export type RemoteControlRequest = {
	baseUrl: string;
	path: string;
	payload?: Record<string, unknown>;
};

export type RemoteGetRequest = {
	baseUrl: string;
	path: string;
};

export type RepoStatusEntry = {
	name: string;
	path: string;
	exists: boolean;
	ok: boolean;
	branch: string;
	head: string;
	headShort: string;
	upstream: string;
	upstreamHead: string;
	upstreamHeadShort: string;
	dirty: boolean;
	ahead: number;
	behind: number;
	updateAvailable: boolean;
	error: string;
	fetched: boolean;
};

export type SystemStatusResponse = {
	ok: boolean;
	monitorStatus: string;
	pollIntervalSeconds: number;
	lastCheckedAt: number;
	repos: RepoStatusEntry[];
	time: number;
};

export type ControllerRPC = {
	bun: RPCSchema<{
		requests: {
			health: {
				params: { baseUrl: string };
				response: RemoteHealthResponse;
			};
			control: {
				params: RemoteControlRequest;
				response: RemoteJsonResponse;
			};
			getJson: {
				params: RemoteGetRequest;
				response: RemoteJsonResponse;
			};
		};
		messages: {};
	}>;
	webview: RPCSchema<{
		requests: {};
		messages: {};
	}>;
};
