const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const [stylusDir, exportPath, libraryPath, flavor, accent] = process.argv.slice(2);
const imported = JSON.parse(fs.readFileSync(exportPath, "utf8"));
const library = fs.readFileSync(libraryPath, "utf8");
const context = vm.createContext({
  console,
  setTimeout,
  clearTimeout,
  performance,
  location: { pathname: "/js/worker.js" },
  navigator: { locks: null },
  close() {},
});
context.self = context;
context.globalThis = context;
context.importScripts = file => {
  const source = fs.readFileSync(path.join(stylusDir, file), "utf8");
  vm.runInContext(source, context, { filename: file });
};
vm.runInContext(fs.readFileSync(path.join(stylusDir, "worker.js"), "utf8"), context, {
  filename: "worker.js",
});

function compile(source, preprocessor, vars, id) {
  return new Promise((resolve, reject) => {
    const port = {
      postMessage(message) {
        if (message.err) reject(message.err);
        else resolve(message.res[0]);
      },
    };
    context.onmessage({
      data: { id, args: ["compileUsercss", source, preprocessor, vars, id, true] },
      ports: [port],
    });
  });
}

function uuid(namespace) {
  const bytes = crypto.createHash("sha256").update(namespace).digest().subarray(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const value = bytes.toString("hex");
  return `${value.slice(0, 8)}-${value.slice(8, 12)}-${value.slice(12, 16)}-${value.slice(16, 20)}-${value.slice(20)}`;
}

(async () => {
  const storage = {
    dbInChromeStorage: true,
    settings: imported[0].settings,
  };

  for (const [offset, original] of imported.slice(1).entries()) {
    const id = offset + 1;
    const style = JSON.parse(JSON.stringify(original));
    const vars = style.usercssData.vars || {};
    if (vars.lightFlavor) vars.lightFlavor.value = "latte";
    if (vars.darkFlavor) vars.darkFlavor.value = flavor;
    if (vars.accentColor) vars.accentColor.value = accent;
    const source = style.sourceCode.replace(
      '@import "https://userstyles.catppuccin.com/lib/lib.less";',
      library,
    );
    style.sections = await compile(source, style.usercssData.preprocessor, vars, id);
    if (!style.sections.length) throw new Error(`${style.name} compiled without sections`);
    style.id = id;
    style._id = uuid(style.usercssData.namespace || style.name);
    style._rev = 1;
    storage[`style-${id}`] = style;
  }

  process.stdout.write(JSON.stringify(storage));
  process.exit(0);
})().catch(error => {
  console.error(error);
  process.exit(1);
});
