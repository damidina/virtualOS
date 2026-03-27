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
		};
		messages: {};
	}>;
	webview: RPCSchema<{
		requests: {};
		messages: {};
	}>;
};
