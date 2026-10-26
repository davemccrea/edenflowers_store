defmodule EdenflowersWeb.SectionIndex do
  @moduledoc """
  Desktop section navigation shared by long storefront pages.
  """

  use EdenflowersWeb, :html

  attr :id, :string, required: true
  attr :sections, :list, required: true

  def section_index(assigns) do
    ~H"""
    <nav
      id={@id}
      phx-hook=".SectionIndex"
      aria-labelledby={@id <> "-heading"}
      class="top-[calc(var(--shy-header-offset,0px)+2rem)] transition-[top] sticky hidden self-start duration-200 ease-out motion-reduce:transition-none md:block"
    >
      <h2 id={@id <> "-heading"} class="text-base-content/75 mb-3 text-sm">{~t"On this page"}</h2>
      <ul class="category-index m-0 list-none p-0">
        <li :for={{id, title} <- @sections}>
          <a href={"##{id}"} class="category-index__link text-base-content block py-1 no-underline">
            <span class="category-index__name font-serif text-lg">{title}</span>
          </a>
        </li>
      </ul>
    </nav>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".SectionIndex">
      // Track scroll position so both anchor jumps and scrolling update the current section.
      export default {
        mounted() {
          const links = [...this.el.querySelectorAll("a[href^='#']")];
          const sections = links.map((link) =>
            document.getElementById(link.hash.slice(1)),
          );

          this.update = () => {
            const line = window.innerHeight * 0.25;
            // The last section may be too short to reach the line.
            const atBottom =
              window.innerHeight + window.scrollY >=
              document.documentElement.scrollHeight - 2;
            const passed = sections.filter(
              (s) => s.getBoundingClientRect().top <= line,
            ).length;
            const current = atBottom ? links.length - 1 : Math.max(passed - 1, 0);

            links.forEach((link, i) => {
              if (i === current) link.setAttribute("aria-current", "location");
              else link.removeAttribute("aria-current");
            });
          };

          this.update();
          document.addEventListener("scroll", this.update, { passive: true });
        },

        updated() {
          this.update();
        },

        destroyed() {
          document.removeEventListener("scroll", this.update);
        },
      };
    </script>
    """
  end
end
