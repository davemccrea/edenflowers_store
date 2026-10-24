defmodule EdenflowersWeb.CoreComponents do
  @moduledoc """
  Core UI components, styled with Tailwind CSS and daisyUI.

  Useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) — available components and themes.
    * [Tailwind CSS](https://tailwindcss.com) — layout, sizing, and spacing utilities.
    * [Heroicons](https://heroicons.com) — see `icon/1`.
    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) — `<.link>`, `<.form>`, and friends.
  """
  use Phoenix.Component
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Phoenix.LiveView.JS

  @image_quality 80
  @image_widths [320, 480, 640, 960, 1280, 1920, 2560, 3840]
  @max_image_dimension 3840
  @gallery_thumb_width 480

  @button_variants %{
    "primary" => "btn-primary",
    "secondary" => "btn-primary btn-outline",
    "ghost" => "btn-ghost",
    "inverse" =>
      "btn-outline border-white/80 text-white [--focus-color:white] hover:border-white hover:bg-white hover:text-base-content focus-visible:border-white focus-visible:bg-white focus-visible:text-base-content",
    "destructive" => "btn-error btn-outline"
  }

  @button_sizes %{
    "sm" => "btn-sm",
    "md" => "btn-md",
    "lg" => "btn-lg"
  }

  @flower_paths Path.wildcard(Path.join(File.cwd!(), "priv/svg/flower-*.svg")) |> Enum.sort()

  @flowers (for path <- @flower_paths, into: %{} do
              raw = File.read!(path)

              viewbox =
                case Regex.run(~r/viewBox="([^"]+)"/, raw, capture: :all_but_first) do
                  [vb] -> vb
                  _ -> "0 0 100 100"
                end

              body =
                raw
                |> String.replace(~r/<\?xml[^?]*\?>\s*/, "")
                |> String.replace(~r|<svg\b[^>]*>|, "")
                |> String.replace(~r|</svg>\s*\z|, "")
                |> String.replace("fill:#000000", "fill:currentColor")

              {Path.basename(path, ".svg"), %{viewbox: viewbox, body: Phoenix.HTML.raw(body)}}
            end)

  for path <- @flower_paths, do: @external_resource(path)

  @doc """
  Renders the standard page wrapper: a width-bounded container with the
  default top/bottom rhythm. Use for every page that doesn't need
  full-bleed sections.
  """
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def container(assigns) do
    ~H"""
    <div class={["container mt-28 mb-24 sm:mt-(--header-clearance) sm:mb-36", @class]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash
        id="welcome-back"
        kind={:info}
        phx-mounted={show("#welcome-back") |> JS.remove_attribute("hidden")}
        hidden
      >
        Welcome Back!
      </.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    # The hook goes by its full name: HEEx only expands ".AutoDismissFlash" in a literal phx-hook.
    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      phx-hook={@kind == :info && "EdenflowersWeb.CoreComponents.AutoDismissFlash"}
      role="alert"
      {@rest}
    >
      <div class={["bg-base-100 text-base-content border-base-300 shadow-base-content/10 border-l-3 flex w-full items-start gap-3 border py-3.5 pr-2 pl-4 shadow-lg sm:w-96", @kind == :info && "border-l-primary", @kind == :error && "border-l-error"]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="text-primary size-5 mt-0.5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="text-error size-5 mt-0.5 shrink-0" />
        <div class="text-pretty min-w-0 flex-1 text-sm leading-relaxed">
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <button
          type="button"
          class="text-base-content/50 touch-target size-8 -my-1 grid shrink-0 place-items-center hover:text-base-content"
          aria-label={~t"close"}
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".AutoDismissFlash">
      /**
       * Dismisses an info flash after a few seconds by running its own phx-click
       * (clear-flash + hide), so a timed dismissal and a click look identical.
       * The countdown pauses while the toast is hovered or holds keyboard focus,
       * and restarts in full afterwards. Errors never get this hook: they stay
       * until the user dismisses them.
       */
      const FLASH_DISMISS_MS = 5000;

      export default {
        mounted() {
          this.pause = () => clearTimeout(this.timer);
          this.resume = () => this.start();

          this.el.addEventListener("mouseenter", this.pause);
          this.el.addEventListener("focusin", this.pause);
          this.el.addEventListener("mouseleave", this.resume);
          this.el.addEventListener("focusout", this.resume);

          this.start();
        },

        // A new message patched into the same toast gets a full countdown.
        updated() {
          this.start();
        },

        start() {
          clearTimeout(this.timer);
          this.timer = setTimeout(() => {
            this.liveSocket.execJS(this.el, this.el.getAttribute("phx-click"));
          }, FLASH_DISMISS_MS);
        },

        destroyed() {
          clearTimeout(this.timer);
        },
      };
    </script>
    """
  end

  @doc """
  Renders a button with navigation support.

  Choose `variant` and `size` by the rules under "Which variant" in DESIGN.md.

  A pressed button shows a spinner while LiveView waits for the server; see
  `forms.css`. Leave out `phx-disable-with`, which would replace the label.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download target rel name value disabled type form)
  attr :class, :any, default: nil
  attr :variant, :string, default: "secondary", values: ~w(primary secondary ghost text inverse destructive)
  attr :size, :string, default: "md", values: ~w(sm md lg)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    classes =
      if assigns.variant == "text" do
        [
          "link-underline-static-body touch-target inline-flex items-center gap-2 hover:decoration-current",
          assigns[:class]
        ]
      else
        [
          "btn gap-2 font-sans font-medium normal-case tracking-normal shadow-none",
          @button_variants[assigns.variant],
          @button_sizes[assigns.size],
          assigns[:class]
        ]
      end

    assigns = assign(assigns, :class, classes)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders the number of characters typed so far into a textarea.
  """
  attr :id, :string, required: true
  attr :textarea, :string, required: true, doc: "the textarea's id"

  def character_count(assigns) do
    ~H"""
    <%!-- The script comes first: after the count, the whitespace it leaves would show as a space before "/max". --%>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".CharacterCount">
      export default {
        mounted() {
          const textarea = document.getElementById(this.el.dataset.textarea);
          const charCountDisplay = this.el;

          updateCharCount();

          textarea.addEventListener("input", updateCharCount);

          function updateCharCount() {
            charCountDisplay.textContent = textarea.value.length;
          }
        },
      };
    </script>
    <span id={@id} phx-hook=".CharacterCount" phx-update="ignore" data-textarea={@textarea}>0</span>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://hexdocs.pm/phoenix_html/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil

  attr :help, :string,
    default: nil,
    doc: "hint text shown under the input, e.g. why a field is asked for"

  attr :value, :any
  attr :button_text, :string, default: nil
  attr :hidden, :boolean, default: false

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               range search select tel text textarea time url week radio-card hidden)

  attr :style, :string,
    default: "default",
    values: ~w(default button-addon)

  attr :field, Phoenix.HTML.FormField, doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :loading, :boolean,
    default: false,
    doc: "shows a loading spinner in the trailing slot (default text-like inputs only)"

  attr :confirmed, :boolean,
    default: false,
    doc: "shows a success check icon in the trailing slot (default text-like inputs only)"

  attr :used?, :boolean,
    default: true,
    doc: "internal: set from Phoenix.Component.used_input?/1 when a :field is given"

  attr :validate_live?, :boolean,
    default: false,
    doc: "opt out of the blur-first debounce and validate from the first keystroke (e.g. search inputs)"

  attr :rest, :global,
    include: ~w(accept autocomplete autocorrect capture cols disabled form inputmode list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step
                phx-blur phx-debounce phx-focus phx-change)

  slot :inner_block

  slot :leading,
    doc: "Text rendered inside the text input on the left (e.g. @). Only supported by the default (text-like) input."

  slot :trailing,
    doc:
      "Adornment rendered inside the text input on the right (e.g. spinner, icon). Only supported by the default (text-like) input."

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    used? = Phoenix.Component.used_input?(field)
    errors = if used?, do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign(:used?, used?)
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <fieldset class={["fieldset mb-2", @hidden && "hidden"]}>
      <label>
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <span class="fieldset-label text-base-content/75 pointer-coarse:min-h-11">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-sm"}
            aria-invalid={@errors != [] && "true"}
            aria-describedby={describedby(@id, @errors, @help)}
            {@rest}
          />{@label}
        </span>
      </label>
      <p :if={@help} id={"#{@id}-help"} class="text-base-content/75 text-sm">{@help}</p>
      <div :if={@errors != []} id={"#{@id}-error"}>
        <.error :for={msg <- @errors}>{msg}</.error>
      </div>
    </fieldset>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <fieldset class={@hidden && "hidden"}>
      <label class="flex flex-col">
        <span :if={@label} class="mb-1">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[@class || "select select-lg w-full text-base", @errors != [] && (@error_class || "select-error")]}
          multiple={@multiple}
          aria-invalid={@errors != [] && "true"}
          aria-describedby={describedby(@id, @errors, @help)}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <p :if={@help} id={"#{@id}-help"} class="text-base-content/75 mt-1.5 text-sm">{@help}</p>
      <div :if={@errors != []} id={"#{@id}-error"}>
        <.error :for={msg <- @errors}>{msg}</.error>
      </div>
    </fieldset>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <fieldset class={@hidden && "hidden"}>
      <label class="flex flex-col">
        <span :if={@label} class="mb-1">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[@class || "textarea textarea-lg w-full text-base", @errors != [] && (@error_class || "textarea-error")]}
          aria-invalid={@errors != [] && "true"}
          aria-describedby={describedby(@id, @errors, @help)}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <p :if={@help} id={"#{@id}-help"} class="text-base-content/75 mt-1.5 text-sm">{@help}</p>
      <div :if={@errors != []} id={"#{@id}-error"}>
        <.error :for={msg <- @errors}>{msg}</.error>
      </div>
    </fieldset>
    """
  end

  def input(%{type: "radio-card"} = assigns) do
    assigns =
      assigns
      |> assign_new(:checked, fn -> nil end)
      |> assign_new(:options, fn -> [] end)
      |> assign_new(:id_prefix, fn -> assigns.id || assigns.name || "radio_card" end)

    ~H"""
    <fieldset class={["flex flex-col", @hidden && "hidden"]}>
      <legend :if={@label} class="mb-1">{@label}</legend>
      <div class="flex flex-col flex-wrap gap-2 md:flex-row">
        <input type="hidden" name={@name} value="" />
        <%= for option <- @options do %>
          <label
            for={"#{@id_prefix}_#{option[:value]}"}
            class={["radio-card border-base-300 flex flex-1 items-center gap-3 border px-4 py-3 transition-all has-[input:checked]:border-primary has-[input:checked]:bg-primary/5 hover:border-primary"]}
          >
            <input
              type="radio"
              name={@name}
              id={"#{@id_prefix}_#{option[:value]}"}
              value={option[:value]}
              checked={option[:value] == to_string(@value)}
              class="radio radio-xs radio-primary"
              {@rest}
            />
            <span>
              {render_slot(@inner_block, option)}
            </span>
          </label>
        <% end %>
      </div>
    </fieldset>
    """
  end

  def input(%{style: "button-addon"} = assigns) do
    ~H"""
    <label class={["input w-full pr-1 text-base", @errors != [] && "input-error", @hidden && "hidden"]}>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class="grow"
        aria-invalid={@errors != [] && "true"}
        aria-describedby={@errors != [] && "#{@id}-error"}
        {@rest}
      />
      <button
        type="submit"
        aria-label={@button_text}
        class="text-base-content/70 touch-target flex flex-none p-2 transition-colors hover:text-base-content"
      >
        <.icon name="hero-arrow-right" class="h-5 w-5" />
      </button>
    </label>
    <div :if={@errors != []} id={"#{@id}-error"}>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <fieldset class={@hidden && "hidden"}>
      <label class="flex flex-col">
        <span :if={@label} class="mb-1">{@label}</span>
        <div class="relative">
          <span
            :if={@leading != []}
            class="text-base-content/60 pointer-events-none absolute inset-y-0 left-3 z-10 flex items-center"
          >
            {render_slot(@leading)}
          </span>
          <input
            type={@type}
            name={@name}
            id={@id}
            value={Phoenix.HTML.Form.normalize_value(@type, @value)}
            class={[@class || "input input-lg w-full text-base", @leading != [] && "pl-8", (@loading or @confirmed or @trailing != []) && "pr-10", @errors != [] && (@error_class || "input-error")]}
            aria-invalid={@errors != [] && "true"}
            aria-describedby={describedby(@id, @errors, @help)}
            phx-debounce={if not @used? and not @validate_live?, do: "blur"}
            inputmode={if @type == "number", do: "numeric"}
            {@rest}
          />
          <div
            :if={@loading or @confirmed or @trailing != []}
            class="pointer-events-none absolute inset-y-0 right-3 z-10 flex items-center"
          >
            <span
              :if={@loading}
              data-testid="input-loading"
              class="loading loading-spinner loading-sm text-base-content/40"
            />
            <span :if={not @loading and @confirmed} data-testid="input-confirmed">
              <.icon name="hero-check-circle-mini" class="text-success size-5" />
            </span>
            {render_slot(@trailing)}
          </div>
        </div>
      </label>
      <%!-- Outside the label, so it describes the field rather than becoming part of its name. --%>
      <p :if={@help} id={"#{@id}-help"} class="text-base-content/75 mt-1.5 text-sm">{@help}</p>
      <div :if={@errors != []} id={"#{@id}-error"}>
        <.error :for={msg <- @errors}>{msg}</.error>
      </div>
    </fieldset>
    """
  end

  defp describedby(id, errors, help) do
    case Enum.filter([help && "#{id}-help", errors != [] && "#{id}-error"], & &1) do
      [] -> nil
      ids -> Enum.join(ids, " ")
    end
  end

  def error(assigns) do
    ~H"""
    <p class="text-error mt-1.5 flex items-center gap-2 text-sm">
      <.icon name="hero-exclamation-circle-mini" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark-solid" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  @doc """
  Renders a hand-drawn botanical illustration inline.

  Tailwind classes drive size (e.g. `h-10 w-10`) and color (e.g. `text-forest-content`),
  since the SVG paths use `fill:currentColor`. Pass `name` to pick a specific
  drawing — the source SVGs ship in the repo at `priv/svg/` and are inlined at
  compile time.

  ## Examples

      <.flower name="flower-30" class="h-32 w-32 text-primary/80" />
  """
  # Credo reads the @flowers lookup as a module attribute declared mid-module.
  # credo:disable-for-next-line Credo.Check.Readability.StrictModuleLayout
  attr :name, :string, required: true, values: Map.keys(@flowers)
  attr :class, :any, default: "h-6 w-6"

  def flower(assigns) do
    %{viewbox: viewbox, body: body} = Map.fetch!(@flowers, assigns.name)
    assigns = assign(assigns, viewbox: viewbox, body: body)

    ~H"""
    <svg
      viewBox={@viewbox}
      class={@class}
      aria-hidden="true"
      focusable="false"
      xmlns="http://www.w3.org/2000/svg"
    >
      {@body}
    </svg>
    """
  end

  @doc """
  Renders an optimised responsive image through the configured Imgproxy server.

  `width`/`height` set the intrinsic dimensions and crop ratio. Responsive
  candidates include smaller standard widths and extend to twice the declared
  width, capped proportionally at 3840 pixels on either edge. Set `sizes` to
  the rendered layout width so the browser can select the right candidate.

  Transformed images use WebP. Output is an `<img>` with `srcset`, wrapped in
  `<picture>` only when `sources` supplies breakpoint-specific crops.
  When `priority` is set the image becomes a LCP candidate
  (`loading="eager"`, `fetchpriority="high"`). Default for non-priority is
  `loading="lazy"` + `decoding="async"`.

  SVGs and external URLs (anything without a `local:///` prefix, such as the
  seed placeholders) skip the `<picture>` machinery and render a plain `<img>`.

  Pass `sources` to swap crops per breakpoint — see `product_card/1`.

  Pass `crop` to cut a region out of the original before resizing, using
  Imgproxy's `width:height:gravity` format. A focus-point gravity keeps a
  subject centred where possible; the crop is shifted to stay inside the
  photo when the subject is near an edge.

  ## Examples

      <.image src="local:///hero.jpg" alt="" width={1920} height={1080} priority />
      <.image src={@product.main_photo_slug} alt={@product.name} width={1000} height={1250} priority />
      <.image src={@slug} alt={~t"Map"} width={1600} height={1880} sizes="(min-width: 768px) 50vw, 100vw" />
      <.image src="local:///portrait.jpg" alt="" width={200} height={200} crop="800:800:fp:0.5:0.3" />
  """
  attr :src, :string, required: true
  attr :alt, :string, required: true
  attr :width, :integer, required: true
  attr :height, :integer, required: true
  attr :sizes, :string, default: "100vw"
  attr :priority, :boolean, default: false
  attr :crop_type, :string, default: "fill", values: ~w(fit fill auto)
  attr :crop, :string, default: nil
  attr :sources, :list, default: []
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(id data-testid)

  def image(assigns) do
    sources =
      if raster_src?(assigns.src) do
        Enum.map(assigns.sources, fn source ->
          %{
            media: Map.fetch!(source, :media),
            srcset: image_srcset(assigns.src, source.width, source.height, assigns.crop_type, assigns.crop)
          }
        end)
      else
        []
      end

    assigns =
      assign(assigns,
        resolved_src: resolve_image_url(assigns.src, assigns.width, assigns.height, assigns.crop_type, assigns.crop),
        srcset: image_srcset(assigns.src, assigns.width, assigns.height, assigns.crop_type, assigns.crop),
        resolved_sources: sources
      )

    ~H"""
    <picture :if={@resolved_sources != []}>
      <source
        :for={source <- @resolved_sources}
        type="image/webp"
        media={source.media}
        srcset={source.srcset}
        sizes={@sizes}
      />
      <.image_tag {assigns} />
    </picture>
    <.image_tag :if={@resolved_sources == []} {assigns} />
    """
  end

  defp svg_src?(src), do: Path.extname(URI.parse(src).path || "") |> String.downcase() == ".svg"

  defp external_src?(src),
    do: not String.starts_with?(src, "local:///")

  defp raster_src?(src), do: not external_src?(src) and not svg_src?(src)

  defp image_tag(assigns) do
    ~H"""
    <img
      src={@resolved_src}
      srcset={@srcset}
      sizes={if @srcset, do: @sizes}
      alt={@alt}
      width={@width}
      height={@height}
      loading={if @priority, do: "eager", else: "lazy"}
      decoding="async"
      fetchpriority={if @priority, do: "high"}
      class={@class}
      {@rest}
    />
    """
  end

  defp image_srcset(src, width, height, crop_type, crop) do
    if raster_src?(src) do
      {max_width, _} = capped_dimensions(width * 2, height * 2)

      (@image_widths ++ [min(width, max_width), max_width])
      |> Enum.filter(&(&1 <= max_width))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map_join(", ", fn candidate_width ->
        candidate_height = max(1, round(height * candidate_width / width))
        url = resolve_image_url(src, candidate_width, candidate_height, crop_type, crop)
        "#{url} #{candidate_width}w"
      end)
    end
  end

  @doc """
  Returns a single Imgproxy URL, built through the same resize/quality
  pipeline as `image/1`.

  For callers that need one concrete URL rather than a responsive image —
  a lightbox target, an `og:image`. Matches `image/1`'s defaults: fill crop
  (pass `"fit"` to keep the whole photo) and WebP. External URLs pass through unchanged; local SVGs are proxied
  without resizing or format conversion.
  """
  def image_url(src, width, height, crop_type \\ "fill") do
    resolve_image_url(src, width, height, crop_type, nil)
  end

  defp resolve_image_url(src, width, height, crop_type, crop) do
    cond do
      external_src?(src) ->
        src

      svg_src?(src) ->
        src |> Imgproxy.new() |> to_string()

      true ->
        {width, height} = capped_dimensions(width, height)

        src
        |> Imgproxy.new()
        |> maybe_crop(crop)
        |> Imgproxy.resize(width, height, type: crop_type)
        |> Imgproxy.add_option(:q, [@image_quality])
        |> Imgproxy.set_extension("webp")
        |> to_string()
    end
  end

  defp maybe_crop(img, nil), do: img
  defp maybe_crop(img, crop), do: Imgproxy.add_option(img, :c, String.split(crop, ":"))

  defp capped_dimensions(width, height) do
    scale = min(1, @max_image_dimension / max(width, height))
    {max(1, floor(width * scale)), max(1, floor(height * scale))}
  end

  @doc """
  Renders a click-to-zoom gallery (PhotoSwipe) of `gallery_photo/1`
  thumbnails in masonry columns.
  """
  attr :id, :string, required: true
  slot :inner_block, required: true

  def gallery(assigns) do
    ~H"""
    <div id={@id} phx-hook=".PhotoGallery" class="columns-2 gap-3 md:columns-3 xl:columns-4">
      {render_slot(@inner_block)}
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".PhotoGallery">
      import PhotoSwipeLightbox from "@/vendor/photoswipe-lightbox.esm";
      import PhotoSwipe from "@/vendor/photoswipe.esm";

      /**
       * Click-to-zoom photo gallery (PhotoSwipe 5).
       *
       * Markup contract: the hook element wraps one <a> per photo, each linking to
       * the full-size image and carrying data-pswp-width/height. Those dimensions
       * must match the served image exactly or PhotoSwipe's zoom maths goes wrong —
       * the page builds both URL and attributes from the same numbers.
       */
      export default {
        mounted() {
          // Passing pswpModule as a value rather than a dynamic import keeps
          // everything in the single esbuild bundle — no runtime chunk fetch.
          this.lightbox = new PhotoSwipeLightbox({
            gallery: this.el,
            children: "a[data-pswp-width]",
            pswpModule: PhotoSwipe,
          });

          // A mouse click leaves the thumbnail focused, so Escape rings it on close.
          // Keyboard activation has detail 0 and keeps PhotoSwipe's focus round trip.
          this.el.addEventListener(
            "click",
            (e) => e.detail && document.activeElement?.blur(),
          );

          // Credit line. PhotoSwipe has no caption of its own, and the plugin that
          // adds one isn't worth a second vendored file for this. It clones the
          // thumbnail's figcaption, photographer link included, so there's one
          // source of truth.
          this.lightbox.on("uiRegister", () => {
            this.lightbox.pswp.ui.registerElement({
              name: "credit",
              appendTo: "root",
              onInit: (el, pswp) => {
                const render = () => {
                  const caption = pswp.currSlide?.data?.element
                    ?.closest("figure")
                    ?.querySelector("figcaption");
                  el.replaceChildren(...(caption?.cloneNode(true).childNodes ?? []));
                };
                pswp.on("change", render);
                render();
              },
            });
          });

          this.lightbox.init();
        },

        destroyed() {
          this.lightbox.destroy();
        },
      };
    </script>
    """
  end

  @doc """
  Renders a thumbnail in a `gallery/1`'s masonry columns, linked to
  the full-size photo it opens. `sizes` assumes the 2/3/4-column layout both
  galleries use.
  """
  attr :photo, :map, required: true, doc: "must respond to :src, :alt, :width, :height"
  attr :class, :any, default: nil

  def gallery_photo(assigns) do
    assigns =
      assign(assigns,
        thumb_width: @gallery_thumb_width,
        thumb_height: round(@gallery_thumb_width * assigns.photo.height / assigns.photo.width)
      )

    ~H"""
    <a
      href={image_url(@photo.src, @photo.width, @photo.height)}
      data-pswp-width={@photo.width}
      data-pswp-height={@photo.height}
      target="_blank"
      rel="noreferrer"
      class={["block", @class]}
    >
      <.image
        src={@photo.src}
        alt={@photo.alt}
        width={@thumb_width}
        height={@thumb_height}
        sizes="(min-width: 96rem) calc(90.5rem / 4), (min-width: 80rem) calc(74.5rem / 4), (min-width: 64rem) calc(59rem / 3), (min-width: 48rem) calc(43rem / 3), (min-width: 40rem) 17.75rem, calc((100vw - 2.5rem) / 2)"
        class="w-full"
      />
      <span class="sr-only">{~t"(opens a larger view)"}</span>
    </a>
    """
  end

  @doc """
  Renders a product card used by both the Featured Blooms carousel (home)
  and the Store grid. One editorial treatment, no surface chrome — the
  photograph is the card; the only interactive accent is the brand
  honey underline on hover. Mobile uses a 4:5 portrait crop for an
  immersive feel; desktop uses a 1:1 square so cards line up cleanly.
  """
  attr :product, :map,
    required: true,
    doc: "must respond to :name, :main_photo_slug, :cheapest_price, :free_delivery, :subscribable, :sold_out?"

  attr :navigate, :string, required: true
  attr :locale, :string, required: true
  attr :heading, :string, default: "h3", doc: "h2 where the card sits directly under the page's h1"

  def product_card(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="group relative isolate block after:content-[''] after:pointer-events-none after:absolute after:inset-0 after:z-10 focus-visible:outline-hidden focus-visible:after:border-primary focus-visible:after:border-2"
    >
      <figure class="bg-cream aspect-[4/5] relative mb-4 overflow-hidden sm:aspect-square">
        <.image
          src={@product.main_photo_slug}
          alt=""
          width={600}
          height={750}
          sources={[%{media: "(min-width: 640px)", width: 600, height: 600}]}
          sizes="(min-width: 640px) 25vw, 50vw"
          class={["h-full w-full object-cover transition duration-700 ease-out group-hover:scale-[1.04]", @product.sold_out? && "opacity-50"]}
        />
      </figure>

      <div class="text-base-content flex flex-col gap-1.5">
        <.dynamic_tag tag_name={@heading} class="card-heading link-underline-group-hover">
          {@product.name}
        </.dynamic_tag>
        <p class="font-serif text-base-content text-lg leading-none">
          <span class="text-base-content/65 font-sans tracking-[0.18em] mr-1 text-xs uppercase">
            {~t"From"}
          </span>
          {Edenflowers.Format.storefront_price(@product.cheapest_price, @locale)}
        </p>
        <p
          :if={@product.sold_out? or @product.free_delivery or @product.subscribable}
          class="text-base-content/65 font-sans tracking-[0.18em] text-xs uppercase leading-snug"
        >
          <span :if={@product.sold_out?} class="text-base-content/80 font-bold" data-testid="sold-out">{~t"Sold out"}</span>
          <span :if={@product.sold_out? and (@product.free_delivery or @product.subscribable)} aria-hidden="true">·</span>
          <span :if={@product.free_delivery}>{~t"Free delivery"}</span>
          <span :if={@product.free_delivery and @product.subscribable} aria-hidden="true">·</span>
          <span :if={@product.subscribable}>{~t"Subscription"}</span>
        </p>
      </div>
    </.link>
    """
  end

  def social_media_links(assigns) do
    ~H"""
    <div class="flex flex-row gap-4">
      <a
        href="https://www.facebook.com/edenflowers.fi/"
        target="_blank"
        rel="noopener noreferrer"
        aria-label={~t"Eden Flowers on Facebook"}
        class="touch-target inline-block transition duration-300 hover:opacity-60"
      >
        <img src="/images/icon-facebook.png" alt="" width="24" height="24" loading="lazy" decoding="async" class="h-6 w-6" />
      </a>
      <a
        href="https://www.instagram.com/edenflowers.fi/"
        target="_blank"
        rel="noopener noreferrer"
        aria-label={~t"Eden Flowers on Instagram"}
        class="touch-target inline-block transition duration-300 hover:opacity-60"
      >
        <img src="/images/icon-instagram.png" alt="" width="24" height="24" loading="lazy" decoding="async" class="h-6 w-6" />
      </a>
    </div>
    """
  end

  @doc """
  Icon-only button. `aria_label` is required so we can't ship a nameless
  button — keyboard/SR users always get an accessible name.
  """
  attr :aria_label, :string, required: true
  attr :class, :any, default: nil
  attr :size, :string, default: "md", values: ~w(sm md lg)
  attr :rest, :global, include: ~w(type disabled name value form popovertarget)
  slot :inner_block, required: true

  def icon_button(assigns) do
    assigns = assign_new(assigns, :type, fn -> "button" end)

    ~H"""
    <.button type={@type} variant="ghost" size={@size} class={["btn-square", @class]} aria-label={@aria_label} {@rest}>
      {render_slot(@inner_block)}
    </.button>
    """
  end

  @doc """
  Cart count badge: a button that opens the cart drawer, with a screen-reader
  accessible name that includes the current count, plus a polite live region
  that announces updates. Replaces the previous unlabelled badge.
  """
  attr :count, :integer, default: 0
  attr :rest, :global, include: ~w(phx-click)
  slot :inner_block, required: true, doc: "Visible content (icon, badge, optional text)"

  def cart_count_badge(assigns) do
    ~H"""
    <button
      type="button"
      class="touch-target group relative flex h-10 w-10 items-center justify-center gap-1 lg:h-auto lg:w-auto lg:gap-2"
      aria-label={cart_aria_label(@count)}
      aria-controls="cart-drawer"
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    <span class="sr-only" aria-live="polite" aria-atomic="true">
      {cart_aria_label(@count)}
    </span>
    """
  end

  defp cart_aria_label(count) when is_integer(count) and count > 0,
    do:
      Gettext.dngettext(EdenflowersWeb.Gettext, "default", "Cart, %{count} item", "Cart, %{count} items", count, %{
        count: count
      })

  defp cart_aria_label(_), do: ~t"Cart, empty"

  @doc """
  Slide-in drawer built on a native modal `<dialog>`, so the browser provides
  the backdrop, focus trapping, Escape and focus return. `autofocus` on the
  dialog lands initial focus on the dialog rather than its first button, which
  iOS Safari would otherwise draw a focus ring around. Open and close it with
  `JS.exec("phx-show" | "phx-hide", to: "#id")`; the script beside it turns those into
  `showModal()` and `close()`, and `layout.css` animates the slide.
  """
  attr :id, :string, required: true
  attr :placement, :string, default: "left", values: ["left", "right"]
  attr :class, :string, default: "bg-base-100 min-w-96"
  attr :label, :string, default: nil
  slot :inner_block, required: true

  def drawer(assigns) do
    ~H"""
    <div
      id={@id}
      phx-show={JS.dispatch("drawer:open", to: "##{@id}-dialog")}
      phx-hide={JS.dispatch("drawer:close", to: "##{@id}-dialog")}
    >
      <%!-- The browser toggles `open` and the drawer script sets `data-closing`; ignoring them stops a LiveView patch from undoing either. --%>
      <dialog
        id={"#{@id}-dialog"}
        aria-label={@label}
        autofocus
        class={"slide-drawer--#{@placement} slide-drawer outline-hidden"}
        phx-mounted={JS.ignore_attributes(["open", "data-closing"])}
      >
        <div id={"#{@id}-content"} class={@class}>
          {render_slot(@inner_block)}
        </div>
      </dialog>
      <script :type={Phoenix.LiveView.ColocatedJS}>
        // Slides a drawer out before closing it. Closing first and animating the exit
        // needs `overlay` transitions, which WebKit lacks: Safari pulls the dialog out
        // of the top layer at once and it vanishes instead of sliding.
        async function closeDrawer(dialog) {
          if (!dialog.open) return;

          dialog.dataset.closing = "";
          await Promise.allSettled(dialog.getAnimations().map((a) => a.finished));

          // A reopen during the slide-out clears the flag and keeps it open.
          if (!("closing" in dialog.dataset)) return;
          delete dialog.dataset.closing;
          dialog.close();
        }

        function openDrawer(dialog) {
          delete dialog.dataset.closing;
          if (!dialog.open) dialog.showModal();
        }

        // The drawer component's phx-show/phx-hide dispatch these to its <dialog>.
        window.addEventListener("drawer:open", (event) => openDrawer(event.target));
        window.addEventListener("drawer:close", (event) => closeDrawer(event.target));

        document.addEventListener(
          "cancel",
          (event) => {
            if (!event.target.matches("dialog.slide-drawer")) return;
            event.preventDefault();
            closeDrawer(event.target);
          },
          true,
        );

        // A tap on a drawer's ::backdrop reports the <dialog> itself as the target,
        // since its content fills the rest of the box. closedby="any" would replace
        // this once Safari supports it.
        document.addEventListener("click", (event) => {
          if (event.target.matches?.("dialog.slide-drawer")) closeDrawer(event.target);
        });

        // Dragging a drawer back toward its edge closes it once it passes a third of
        // its width or is flicked. Vertical drags stay scrolls (touch-action in layout.css).
        document.addEventListener("pointerdown", (down) => {
          if (down.pointerType === "mouse") return;
          const dialog = down.target.closest?.("dialog.slide-drawer");
          if (!dialog?.open) return;

          const direction = dialog.classList.contains("slide-drawer--left") ? -1 : 1;
          let offset = 0;
          const listening = new AbortController();

          const move = (event) => {
            if (event.pointerId !== down.pointerId) return;
            offset = Math.max(0, (event.clientX - down.clientX) * direction);
            dialog.style.transition = "none";
            dialog.style.translate = `${offset * direction}px 0`;
          };

          const end = (event) => {
            if (event.pointerId !== down.pointerId) return;
            listening.abort();

            const velocity = offset / (event.timeStamp - down.timeStamp);
            const swiped = offset > dialog.offsetWidth / 3 || velocity > 0.5;

            // Clearing both in one go lets the CSS transition carry the drawer from
            // where the finger left it, either out or back into place.
            dialog.style.removeProperty("transition");
            dialog.style.removeProperty("translate");
            if (event.type === "pointerup" && swiped) closeDrawer(dialog);
          };

          const options = { signal: listening.signal };
          window.addEventListener("pointermove", move, options);
          window.addEventListener("pointerup", end, options);
          window.addEventListener("pointercancel", end, options);
        });

        // On touch screens, swiping right pulls the admin navigation drawer out under the
        // finger, and lets go the same way as the swipe-to-close. The left
        // edge is left to the iOS swipe back, text fields to selecting text, and
        // anything scrolled sideways to scrolling back. These are touch events rather
        // than pointer events so the first sideways move can stop the browser from
        // starting a scroll, which would cancel the swipe.
        document.addEventListener("touchstart", (start) => {
          if (start.touches.length > 1) return;
          const touch = start.changedTouches[0];
          if (touch.clientX < 20) return;
          if (start.target.closest?.("input, textarea, select, [contenteditable]"))
            return;
          if (scrolledSideways(start.target)) return;
          const dialog = navDrawer();
          if (!dialog || document.querySelector("dialog[open]")) return;

          let offset = 0;
          const listening = new AbortController();
          const sameTouch = (event) =>
            [...event.changedTouches].find((t) => t.identifier === touch.identifier);

          const move = (event) => {
            const moved = sameTouch(event);
            if (!moved) return;
            const dx = moved.clientX - touch.clientX;
            const dy = moved.clientY - touch.clientY;

            if (!dialog.open) {
              if (dx === 0 && dy === 0) return;
              // The first move decides: only a mostly rightward one is a swipe.
              if (dx <= Math.abs(dy)) return listening.abort();
              dialog.style.transition = "none";
              openDrawer(dialog);
            }

            event.preventDefault();
            offset = Math.min(Math.max(dx, 0), dialog.offsetWidth);
            dialog.style.translate = `${offset - dialog.offsetWidth}px 0`;
          };

          const end = (event) => {
            if (!sameTouch(event)) return;
            listening.abort();
            if (!dialog.open) return;

            const velocity = offset / (event.timeStamp - start.timeStamp);
            const swiped = offset > dialog.offsetWidth / 3 || velocity > 0.5;

            dialog.style.removeProperty("transition");
            dialog.style.removeProperty("translate");
            if (event.type !== "touchend" || !swiped) closeDrawer(dialog);
          };

          const options = { signal: listening.signal };
          window.addEventListener("touchmove", move, { ...options, passive: false });
          window.addEventListener("touchend", end, options);
          window.addEventListener("touchcancel", end, options);
        });

        // Only the admin opens its drawer by swipe; from lg up it has a persistent
        // sidebar instead.
        function navDrawer() {
          if (matchMedia("(min-width: 64rem)").matches) return null;
          return document.getElementById("admin-nav-drawer-dialog");
        }

        function scrolledSideways(element) {
          for (; element; element = element.parentElement) {
            if (element.scrollLeft > 0) return true;
          }
          return false;
        }
      </script>
    </div>
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js, to: selector)
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 150,
      transition:
        {"transition ease-in duration-150", "opacity-100 translate-0",
         "opacity-0 motion-safe:translate-y-2 motion-safe:sm:translate-x-6 motion-safe:sm:translate-y-0"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(EdenflowersWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(EdenflowersWeb.Gettext, "errors", msg, opts)
    end
  end
end
