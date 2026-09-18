/** SVG <text> には自動折返しがないので、簡易的に最大2行+省略記号で近似する。 */
export function wrapLabel(text: string, maxCharsPerLine = 15): [string] | [string, string] {
  const trimmed = text.trim();
  if (trimmed.length <= maxCharsPerLine) return [trimmed];

  const words = trimmed.split(/\s+/);
  if (words.length <= 1) {
    return [trimmed.slice(0, maxCharsPerLine), `${trimmed.slice(maxCharsPerLine, maxCharsPerLine * 2 - 1)}…`];
  }

  let line1 = '';
  let i = 0;
  for (; i < words.length; i++) {
    const next = line1 ? `${line1} ${words[i]}` : words[i];
    if (next.length > maxCharsPerLine && line1) break;
    line1 = next;
  }
  let line2 = words.slice(i).join(' ');
  if (line2.length > maxCharsPerLine) {
    line2 = `${line2.slice(0, maxCharsPerLine - 1)}…`;
  }
  return line2 ? [line1, line2] : [line1];
}
