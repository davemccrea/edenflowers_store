const annotation = (node) => {
  if (node.nodeType !== 8) return null;
  const text = node.nodeValue.trim();
  const open = text.match(/^<([^>]+)>\s+(.+:\d+?)(?:\s+\([^)]*\))?$/);
  return open ? { name: open[1], location: open[2], node } : null;
};

const caller = (node) => {
  let previous = node.previousSibling;
  while (previous?.nodeType === 3 && !previous.nodeValue.trim()) {
    previous = previous.previousSibling;
  }
  return previous?.nodeType === 8
    ? previous.nodeValue
        .trim()
        .match(/^@caller\s+(.+:\d+?)(?:\s+\([^)]*\))?$/)?.[1]
    : null;
};

const enclosingComponents = (element) => {
  const components = [];
  let depth = 0;
  let node = element;
  while ((node = node.previousSibling || node.parentNode)) {
    if (node.nodeType === 8 && /^<\/[^>]+>$/.test(node.nodeValue.trim())) {
      depth++;
    } else {
      const component = annotation(node);
      if (!component) continue;
      if (depth > 0) depth--;
      else components.push(component);
    }
  }
  return components;
};

export const findHeexSource = (element) => {
  let mappedElement = element;
  while (mappedElement && !mappedElement.getAttribute("data-phx-loc")) {
    mappedElement = mappedElement.parentElement;
  }
  if (!mappedElement) return null;
  const components = enclosingComponents(mappedElement);
  const source = components[0];
  if (!source) return null;
  const component = components.find(({ name }) => !name.startsWith(":"));
  return {
    component: component?.name,
    mappedElement,
    file: source.location.replace(/:\d+$/, ""),
    location: source.location.replace(
      /:\d+$/,
      `:${mappedElement.getAttribute("data-phx-loc")}`,
    ),
    components,
  };
};

const frameworkDetails = (source) => {
  const tree = [];
  for (const component of source.components) {
    const isSlot = component.name.startsWith(":");
    const call = caller(component.node);
    if (call) tree.push(`Called from: ${call} (${component.name})`);
    else if (!isSlot) {
      tree.push(`Entrypoint: ${component.name}`);
      break;
    }
  }
  return tree.join("\n");
};

export const selectorFor = (element) => {
  const parts = [];
  for (let node = element; node; node = node.parentElement) {
    if (node.id) {
      parts.unshift(`#${CSS.escape(node.id)}`);
      break;
    }
    const tag = node.tagName.toLowerCase();
    const siblings = node.parentElement
      ? [...node.parentElement.children].filter(
          (sibling) => sibling.tagName === node.tagName,
        )
      : [node];
    parts.unshift(
      siblings.length > 1
        ? `${tag}:nth-of-type(${siblings.indexOf(node) + 1})`
        : tag,
    );
  }
  return parts.join(" > ");
};

const describeElement = (element) => {
  const attributes = [
    "id",
    "class",
    "role",
    "aria-label",
    "name",
    "type",
    "phx-click",
    "phx-change",
    "phx-hook",
  ].flatMap((name) => {
    const value = element.getAttribute(name);
    return value ? [`${name}=${JSON.stringify(value)}`] : [];
  });
  const text = (element.textContent || "").replace(/\s+/g, " ").trim();
  const excerpt = text.length > 120 ? `${text.slice(0, 117)}...` : text;
  return [
    [element.tagName.toLowerCase(), ...attributes].join(" "),
    excerpt && `Text: ${JSON.stringify(excerpt)}`,
  ]
    .filter(Boolean)
    .join("\n");
};

export const elementReference = (element, document) => {
  const source = findHeexSource(element);
  const lines = [
    `Page: ${document.location.href}`,
    `Element: ${describeElement(element)}`,
    `Selector: ${selectorFor(element)}`,
  ];
  if (source) {
    const fallback =
      source.mappedElement !== element ? " (nearest annotated ancestor)" : "";
    lines.push(
      `Source: ${source.location}${fallback}`,
      frameworkDetails(source),
    );
  }
  return lines.filter(Boolean).join("\n");
};
