import { pathToFileURL } from "node:url";
export const url = pathToFileURL(__filename).href;
