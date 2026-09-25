// wrangler and @cloudflare/vitest-pool-workers turn `import x from "*.wasm"`
// into a precompiled WebAssembly.Module (Workers forbid compiling WASM from bytes at runtime).
declare module "*.wasm" {
  const module: WebAssembly.Module;
  export default module;
}
