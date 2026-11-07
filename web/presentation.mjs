// Only the presentation changes. Original UTF-8 bytes remain independently owned.
const decoder = new TextDecoder("utf-8", { fatal: true });
export function visibleOutput(bytes, format, printer) {
    const text = decoder.decode(bytes);
    if (format === "ir") {
        return text.replace(/[\x00-\x1f\x7f]/g, control => {
            const code = control.charCodeAt(0);
            return printer.encodeMap.get(code) + (code === 30 ? "\n" : "");
        });
    }
    // Escape controls cannot style the page or disguise the copied raw output.
    return text.replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, control => printer.encodeMap.get(control.charCodeAt(0)));
}
export function irLegend(printer) {
    return [[28,"FS"], [29,"GS"], [30,"RS"], [31,"US"], [27,"ESC"]]
        .map(([code, name]) => `${printer.encodeMap.get(code)} ${name}`).join("    ");
}
