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
  const definitions = new Map();
  for (const component of source.components) {
    const isSlot = component.name.startsWith(":");
    if (!isSlot) definitions.set(component.name, component.location);
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

${tree.join("\n")}

Component definition locations:

${[...definitions]
  .sort(([a], [b]) => a.localeCompare(b))
  .map(([name, location]) => `${name}: ${location}`)
  .join("\n")}`;
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
  const page = [
    "The user is looking at a page.",
    block("url", document.location.href),
  ];
  const comments = document.createTreeWalker(document, 128);
  let node;
  while ((node = comments.nextNode())) {
    const component = annotation(node);
    if (
      !component ||
      component.name.startsWith(":") ||
      component.location.includes("layouts") ||
      caller(node)
    )
      continue;
    let details = `Page render information:\nentrypoint: ${component.name}\nsource: ${component.location}`;
    const views = [...document.querySelectorAll("[data-phx-pid]")];
    if (views.length) {
      details += "\n\nThe page renders the following LiveViews:\n";
      details += views
        .map(
          (view) =>
            `* ${view.hasAttribute("data-phx-main") ? "Main " : ""}LiveView #${view.id} with PID ${view.getAttribute("data-phx-pid")}`,
        )
        .join("\n");
      details +=
        '\nCall the get_docs tool with "Phoenix.LiveView.Debug" to learn how to debug those.';
    }
    page.push(block("framework-details", details));
    break;
  }
  const reference = [
    block(
      "description",
      `The user has selected a ${element.tagName.toLowerCase()} element.`,
    ),
    block("selector", selectorFor(element)),
  ];
  if (source)
    reference.push(block("framework-details", frameworkDetails(source)));
  const text = element.textContent?.trim();
  if (text) reference.push(block("text-content", text));
  return `<context name="current-page">\n${page.join("\n")}\n</context>\n\n<references>\n<reference id="0" type="selected_element">\n${reference.join("\n")}\n</reference>\n</references>`;
};
