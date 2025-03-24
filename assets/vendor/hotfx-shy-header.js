/*
 * This code was adapted from https://github.com/hot-page/fx/tree/main/hotfx-shy-header
 * Retrieved on: 2025-03-24
 *
 * Modifications made:
 * - Stripped out comments
 * - Modified hotfx-shy-header class
 * - Modified scoll variables
 */

const sheet = new CSSStyleSheet();
sheet.replace(`
  hotfx-shy-header {
    display: flex;
    position: fixed;
    top: 0;
    z-index: 100;
    width: 100vw;
    transition: transform 0.2s ease-out;
  }

  hotfx-shy-header.hidden {
    transform: translateY(-100%);
  }
`);
document.adoptedStyleSheets.push(sheet);

class HotFXShyHeader extends HTMLElement {
  #lastScroll = 0;
  #lastMaxScroll = 0;

  connectedCallback() {
    document.addEventListener("scroll", this.#handleScroll);
  }

  disconnectedCallback() {
    document.removeEventListener("scroll", this.#handleScroll);
  }

  #handleScroll = () => {
    if (window.scrollY > Math.max(150, this.#lastScroll)) {
      this.classList.add("hidden");
    } else if (window.scrollY < this.#lastMaxScroll - 150) {
      this.classList.remove("hidden");
      this.#lastMaxScroll = window.scrollY;
    }
    this.#lastScroll = window.scrollY;
    if (window.scrollY > this.#lastMaxScroll) {
      this.#lastMaxScroll = window.scrollY;
    }
  };
}

customElements.define("hotfx-shy-header", HotFXShyHeader);
