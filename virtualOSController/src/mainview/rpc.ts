import { Electroview } from "electrobun/view";
import type { ControllerRPC } from "../shared/rpc";

const controllerRpc = Electroview.defineRPC<ControllerRPC>({
	maxRequestTime: 7000,
	handlers: {
		requests: {},
		messages: {},
	},
});

new Electroview({ rpc: controllerRpc });

export { controllerRpc };
