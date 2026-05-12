defmodule EdenflowersWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders the standard page wrapper: a width-bounded container with the
  default top/bottom rhythm. Use for every page that doesn't need
  full-bleed sections.
  """
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def container(assigns) do
    ~H"""
    <div class={["mt-[calc(var(--header-height)+var(--spacing)*12)] container mb-36", @class]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders flash messages as toast notifications.

  Also handles the disconnected/reconnected banner via the FlashHandler hook.
  """
  def flash_group(assigns) do
    ~H"""
    <div
      id="flash-group"
      class="z-[100] fixed inset-x-0 bottom-6 flex flex-col items-center gap-3 px-4"
      role="region"
      aria-label={~t"Notifications"}
      phx-hook="FlashHandler"
      data-disconnected-message={~t"Disconnected from server. Reconnecting..."}
      data-reconnected-message={~t"Reconnected"}
    >
      <div
        :for={{key, msg} <- @flash}
        id={"flash-#{key}"}
        class="toast-item"
        data-key={key}
        data-duration="5000"
        role={flash_role(key)}
      >
        <div class="toast-item__head">
          <p class="toast-item__eyebrow">{flash_label(key)}</p>
          <button class="toast-item__dismiss" aria-label={~t"Dismiss"} data-dismiss>
            <.icon name="hero-x-mark" />
          </button>
        </div>
        <p class="toast-item__body">{msg}</p>
      </div>
    </div>
    """
  end

  # Errors interrupt; everything else waits politely. WCAG 4.1.3.
  defp flash_role("error"), do: "alert"
  defp flash_role(_), do: "status"

  # Severity → eyebrow label. Restrained, conventional words — the message
  # itself does the heavy lifting; the eyebrow just orients the reader.
  defp flash_label("error"), do: ~t"Couldn't complete"
  defp flash_label("warning"), do: ~t"Notice"
  defp flash_label("success"), do: ~t"Confirmed"
  defp flash_label(_), do: ~t"Note"

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled type)
  attr :class, :any, default: nil
  attr :variant, :string, default: "secondary", values: ~w(primary secondary ghost)
  attr :size, :string, default: "md", values: ~w(sm md lg)
  slot :inner_block, required: true

  @button_variants %{
    "primary" => "btn-primary",
    "secondary" => "btn-primary btn-soft",
    "ghost" => "btn-ghost"
  }

  @button_sizes %{
    "sm" => "btn-sm",
    "md" => "",
    "lg" => "btn-lg"
  }

  def button(%{rest: rest} = assigns) do
    classes = ["btn", @button_variants[assigns.variant], @button_sizes[assigns.size], assigns[:class]]

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

  attr :rest, :global, include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step
                phx-blur phx-focus phx-change)

  slot :inner_block

  slot :trailing,
    doc:
      "Adornment rendered inside the text input on the right (e.g. spinner, icon). Only supported by the default (text-like) input."

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
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
        <span class="fieldset-label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-sm"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
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
          class={[@class || "select w-full", @errors != [] && (@error_class || "select-error")]}
          multiple={@multiple}
          aria-invalid={@errors != []}
          aria-describedby={@errors != [] && "#{@id}-error"}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <div :if={@errors != []} id={"#{@id}-error"}>
        <.error :for={msg <- @errors}>{msg}</.error>
      </div>
    </fieldset>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <fieldset class={["fieldset mb-2", @hidden && "hidden"]}>
      <label>
        <span :if={@label} class="fieldset-label mb-1">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[@class || "textarea w-full", @errors != [] && (@error_class || "textarea-error")]}
          aria-invalid={@errors != []}
          aria-describedby={@errors != [] && "#{@id}-error"}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
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
    <fieldset class={["flex flex-col gap-1", @hidden && "hidden"]}>
      <span :if={@label}>{@label}</span>
      <div class="flex flex-col flex-wrap gap-2 md:flex-row">
        <input type="hidden" name={@name} value="" />
        <%= for option <- @options do %>
          <label
            for={"#{@id_prefix}_#{option[:value]}"}
            class={["border-base-300 flex flex-1 cursor-pointer items-center gap-3 rounded border px-4 py-3 transition-all has-[input:checked]:border-primary has-[input:checked]:bg-primary/5 has-[input:checked]:border-primary hover:border-primary"]}
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
    <fieldset class={["join w-full", @hidden && "hidden"]}>
      <label class="input join-item w-full">
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[@errors != [] && "input-error"]}
          aria-invalid={@errors != []}
          aria-describedby={@errors != [] && "#{@id}-error"}
          {@rest}
        />
      </label>
      <button class="btn btn-primary join-item z-50">{@button_text}</button>
    </fieldset>
    <div :if={@errors != []} id={"#{@id}-error"}>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <fieldset class={@hidden && "hidden"}>
      <label class="flex flex-col">
        <span :if={@label} class="mb-1">{@label}</span>
        <div class="relative">
          <input
            type={@type}
            name={@name}
            id={@id}
            value={Phoenix.HTML.Form.normalize_value(@type, @value)}
            class={[@class || "input input-lg w-full", (@loading or @confirmed or @trailing != []) && "pr-10", @errors != [] && (@error_class || "input-error")]}
            aria-invalid={@errors != []}
            aria-describedby={@errors != [] && "#{@id}-error"}
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
      <div :if={@errors != []} id={"#{@id}-error"}>
        <.error :for={msg <- @errors}>{msg}</.error>
      </div>
    </fieldset>
    """
  end

  # Helper used by inputs to generate form errors
  def error(assigns) do
    ~H"""
    <p class="text-error mt-1.5 flex items-center gap-2 text-sm">
      <.icon name="hero-exclamation-circle-mini" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-base-content/80 text-sm">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a breadcrumb navigation component using DaisyUI.

  ## Examples

      <.breadcrumb>
        <:item navigate={~p"/"} label={~t"Home"} />
        <:item navigate={~p"/store"} label={~t"Store"} />
        <:item label={~t"Product Name"} />
      </.breadcrumb>

  The last item is automatically marked as the current page with `aria-current="page"`.
  """
  attr :class, :string, default: "mb-8 text-sm", doc: "Additional CSS classes for the breadcrumbs wrapper"

  slot :item, required: true, doc: "Individual breadcrumb items" do
    attr :navigate, :string, doc: "Navigation path (optional for current page)"
    attr :label, :string, required: true, doc: "The breadcrumb label text"
  end

  def breadcrumb(assigns) do
    ~H"""
    <div class={["breadcrumbs", @class]} role="navigation" aria-label="Breadcrumb" data-testid="breadcrumb">
      <ul>
        <%= for {item, index} <- Enum.with_index(@item) do %>
          <li :if={index == length(@item) - 1} aria-current="page" data-testid="breadcrumb-current">
            {item.label}
          </li>
          <li :if={index < length(@item) - 1}>
            <.link navigate={item.navigate} data-testid={"breadcrumb-link-#{index}"}>
              {item.label}
            </.link>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table-zebra table">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">{~t"Actions"}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td :for={col <- @col} phx-click={@row_click && @row_click.(row)} class={@row_click && "hover:cursor-pointer"}>
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
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

  @flower_paths Path.wildcard(Path.join(File.cwd!(), "priv/svg/flower-*.svg")) |> Enum.sort()
  @flower_names Enum.map(@flower_paths, &Path.basename(&1, ".svg"))
  @flower_count length(@flower_names)

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
  Renders a hand-drawn botanical illustration inline.

  Tailwind classes drive size (e.g. `h-10 w-10`) and color (e.g. `text-forest-content`),
  since the SVG paths use `fill:currentColor`. Selection is deterministic from
  `seed` — same seed always yields the same drawing — or pass an explicit `name`
  like `"flower-09"` to pin one. The source SVGs ship in the repo at `priv/svg/`
  and are inlined at compile time.

  ## Examples

      <.flower seed="cart-empty" class="h-32 w-32 text-primary/80" />
      <.flower name="flower-09" class="h-10 w-10 text-forest-content/70" />
  """
  attr :seed, :any, default: nil
  attr :name, :string, default: nil, values: [nil | @flower_names]
  attr :class, :any, default: "h-6 w-6"

  def flower(assigns) do
    %{viewbox: viewbox, body: body} = Map.fetch!(@flowers, assigns.name || flower_pick(assigns.seed))
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

  defp flower_pick(nil), do: "flower-01"
  defp flower_pick(seed), do: Enum.at(@flower_names, :erlang.phash2(seed, @flower_count))

  @doc """
  Renders a product card used by both the Featured Blooms carousel (home)
  and the Store grid. One editorial treatment, no surface chrome — the
  photograph is the card; the only interactive accent is the brand
  honey underline on hover. Mobile uses a 4:5 portrait crop for an
  immersive feel; desktop uses a 1:1 square so cards line up cleanly.

  `from_price?: true` prefixes the price with the "From" preposition,
  appropriate when the value comes from `cheapest_price` across variants.
  """
  attr :product, :map, required: true, doc: "must respond to :name, :image_slug, :cheapest_price"
  attr :navigate, :string, required: true
  attr :from_price?, :boolean, default: true
  attr :class, :any, default: nil

  def product_card(assigns) do
    ~H"""
    <.link navigate={@navigate} class={["group block focus:outline-none", @class]}>
      <figure class="bg-cream aspect-[4/5] relative mb-4 overflow-hidden sm:aspect-square">
        <img
          src={@product.image_slug |> Imgproxy.new() |> Imgproxy.resize(600, 750, type: "fill") |> to_string()}
          alt=""
          loading="lazy"
          class="block h-full w-full object-cover transition duration-700 ease-out group-hover:scale-[1.04] sm:hidden"
        />
        <img
          src={@product.image_slug |> Imgproxy.new() |> Imgproxy.resize(600, 600, type: "fill") |> to_string()}
          alt=""
          loading="lazy"
          class="hidden h-full w-full object-cover transition duration-700 ease-out group-hover:scale-[1.04] sm:block"
        />
      </figure>

      <div class="text-base-content flex flex-col gap-1.5">
        <h3 class="card-title link-underline-group-hover-display">
          {@product.name}
        </h3>
        <p class="font-serif text-base-content/65 text-base italic leading-none">
          <span :if={@from_price?} class="font-sans tracking-[0.18em] mr-1 text-xs uppercase not-italic">
            {~t"From"}
          </span>
          {Edenflowers.Utils.format_money(@product.cheapest_price)}
        </p>
      </div>
    </.link>
    """
  end

  @doc """
  Renders a category tile: a clickable image card with an overlaid label.

  ## Examples

      <.category_tile navigate={~p"/store"} label="Store" image_src="..." />
  """
  attr :navigate, :string, required: true
  attr :label, :string, required: true
  attr :image_src, :string, required: true

  def category_tile(assigns) do
    ~H"""
    <.link navigate={@navigate} class="group relative overflow-hidden">
      <img
        src={@image_src}
        class="h-72 w-full object-cover transition duration-500 group-hover:scale-102 sm:h-80 md:h-96"
        alt={@label}
      />
      <div class="absolute inset-0 transition duration-500 group-hover:bg-black/10" />
      <div class="absolute inset-0 flex items-end p-6">
        <h3 class="tile-title text-white">{@label}</h3>
      </div>
    </.link>
    """
  end

  attr :size, :integer, default: 5

  def social_media_links(assigns) do
    ~H"""
    <div class="flex flex-row gap-4">
      <a
        href="https://www.facebook.com/edenflowers.fi/"
        target="_blank"
        rel="noopener noreferrer"
        aria-label="Eden Flowers on Facebook"
      >
        <img
          class={"h-#{@size} w-#{@size}"}
          src={
            "local:///facebook_logo_bw_128px.png"
            |> Imgproxy.new()
            |> Imgproxy.resize(128, 128, type: "fill")
            |> to_string()
          }
          alt=""
        />
      </a>
      <a
        href="https://www.instagram.com/edenflowers.fi/"
        target="_blank"
        rel="noopener noreferrer"
        aria-label="Eden Flowers on Instagram"
      >
        <img
          class={"h-#{@size} w-#{@size}"}
          src={
            "local:///instagram_logo_bw_128px.png"
            |> Imgproxy.new()
            |> Imgproxy.resize(128, 128, type: "fill")
            |> to_string()
          }
          alt=""
        />
      </a>
    </div>
    """
  end

  @doc """
  Icon-only button. `aria_label` is required so we can't ship a nameless
  button — keyboard/SR users always get an accessible name.
  """
  attr :aria_label, :string, required: true
  attr :class, :any, default: "h-12 w-12 cursor-pointer"
  attr :rest, :global, include: ~w(type disabled name value form)
  slot :inner_block, required: true

  def icon_button(assigns) do
    assigns = assign_new(assigns, :type, fn -> "button" end)

    ~H"""
    <button type={@type} class={@class} aria-label={@aria_label} {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Disclosure trigger — a button that controls a collapsible region (drawer,
  menu, dialog). Sets `aria-expanded` and `aria-controls` so AT users know
  the relationship. State must be tracked outside this component (LV
  doesn't know if the drawer is open).
  """
  attr :aria_label, :string, required: true
  attr :controls, :string, required: true, doc: "id of the controlled element"
  attr :expanded, :boolean, default: false
  attr :class, :any, default: "h-12 w-12 cursor-pointer"
  attr :rest, :global, include: ~w(phx-click phx-target type)
  slot :inner_block, required: true

  def disclosure_trigger(assigns) do
    ~H"""
    <button
      type="button"
      class={@class}
      aria-label={@aria_label}
      aria-controls={@controls}
      aria-expanded={to_string(@expanded)}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
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
      class="group relative flex h-10 w-10 cursor-pointer items-center justify-center gap-1 lg:h-auto lg:w-auto lg:gap-2"
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

  @placement %{
    "left" => %{
      class: "justify-start",
      transition_in: "translate-x-0 opacity-100",
      transition_out: "-translate-x-full opacity-0"
    },
    "right" => %{
      class: "justify-end",
      transition_in: "translate-x-0 opacity-100",
      transition_out: "translate-x-full opacity-0"
    },
    "top" => %{
      class: "items-start",
      transition_in: "translate-y-0 opacity-100",
      transition_out: "-translate-y-full opacity-0"
    },
    "bottom" => %{
      class: "items-end",
      transition_in: "translate-y-0 opacity-100",
      transition_out: "translate-y-full opacity-0"
    }
  }

  attr :id, :string, required: true
  attr :placement, :string, default: "left", values: ["left", "right", "top", "bottom"]
  attr :class, :string, default: "bg-base-100 min-w-96"
  attr :label, :string, default: nil
  slot :inner_block, required: true

  def drawer(%{placement: placement} = assigns) do
    assigns =
      assigns
      |> assign(:transition, "transition-all duration-250 ease-in-out")
      |> assign(:placement_class, @placement[placement].class)
      |> assign(:transition_in, @placement[placement].transition_in)
      |> assign(:transition_out, @placement[placement].transition_out)
      |> assign(:time, 250)

    ~H"""
    <div
      id={@id}
      phx-window-keydown={JS.exec("phx-hide", to: "##{@id}")}
      phx-key="Escape"
      phx-show={
        %JS{}
        |> JS.show(to: "##{@id}-backdrop", transition: {@transition, "opacity-0", "opacity-100"}, time: @time)
        |> JS.show(
          to: "##{@id}-dialog",
          display: "flex",
          transition: {@transition, @transition_out, @transition_in},
          time: @time
        )
        |> JS.focus(to: "##{@id}-top")
        |> JS.add_class("overflow-hidden", to: "html")
      }
      phx-hide={
        %JS{}
        |> JS.hide(to: "##{@id}-backdrop", transition: {@transition, "opacity-100", "opacity-0"}, time: @time)
        |> JS.hide(
          to: "##{@id}-dialog",
          transition: {@transition, @transition_in, @transition_out},
          time: @time
        )
        |> JS.remove_class("overflow-hidden", to: "html")
        |> JS.pop_focus()
      }
      class="z-100 relative"
    >
      <div id={"#{@id}-backdrop"} class="bg-black/30 fixed inset-0 hidden"></div>
      <div
        id={"#{@id}-dialog"}
        role="dialog"
        aria-modal="true"
        aria-label={@label}
        class={"#{@placement_class} fixed inset-0 hidden outline-hidden"}
      >
        <.focus_wrap id={"#{@id}-body"}>
          <div tabindex="0" id={"#{@id}-top"}></div>
          <div phx-click-away={JS.exec("phx-hide", to: "##{@id}")} id={"#{@id}-content"} class={@class}>
            {render_slot(@inner_block)}
          </div>
        </.focus_wrap>
      </div>
    </div>
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300", "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(EdenflowersWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(EdenflowersWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
