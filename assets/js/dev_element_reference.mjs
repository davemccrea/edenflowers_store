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
  const components = enclosingComponents(element);
  const source = components[0];
  if (!source) return null;
  const component = components.find(({ name }) => !name.startsWith(":"));
  return {
    component: component?.name,
    file: source.location.replace(/:\d+$/, ""),
    location: source.location.replace(
      /:\d+$/,
      `:${element.getAttribute("data-phx-loc")}`,
    ),
    components,
  };
};

const frameworkDetails = (source) => {
  const tree = [];
  for (const component of source.components) {
    const isSlot = component.name.startsWith(":");
    const call = caller(component.node);
    if (call) tree.push(`${call}: ${component.name}`);
    else if (!isSlot) {
      tree.push(`entrypoint: ${component.name}`);
      break;
    }
  }
  return `The element source is at:

${source.location}

Component rendering tree (from innermost to outermost):

${tree.join("\n")}`;
};

const selectorFor = (element) => {
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

const block = (name, text) => `<${name}>\n${text}\n</${name}>`;

export const elementReference = (element, document) => {
  const source = findHeexSource(element);
  const page = block("url", document.location.href);
  const reference = [block("selector", selectorFor(element))];
  if (source)
    reference.push(block("framework-details", frameworkDetails(source)));
  return `<context name="current-page">\n${page}\n</context>\n\n<references>\n<reference id="0" type="selected_element">\n${reference.join("\n")}\n</reference>\n</references>`;
};
