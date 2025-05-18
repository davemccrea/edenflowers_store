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
  use Gettext, backend: EdenflowersWeb.Gettext

  alias Phoenix.LiveView.JS
  alias EdenflowersWeb.LiveToast

  @doc """
  Renders a component for dynamic, client-side alerts.

  This component is typically used for displaying alerts that are not part of
  the standard Phoenix flash message lifecycle. For example, you might use this
  for real-time notifications triggered by client-side events or LiveView pushes
  that require a more persistent or distinct UI treatment than flash messages.
  """
  def alert_group(assigns) do
    ~H"""
    <div id="alert-group" phx-hook="AlertHandler" />
    """
  end

  @doc """
  Renders the Phoenix flash messages.

  Flash messages are typically used for feedback after an action, such as a successful
  form submission or an error during an operation. Due to limitations in the Phoenix
  flash system, only one type of flash message (e.g., one :info or one :error) can be
  displayed at a time when set directly on the connection.

  It also includes a built-in alert for disconnection/reconnection status.
  """
  def flash_group(assigns) do
    flash = Enum.map(assigns.flash, fn {key, msg} -> LiveToast.new(key, msg) end)
    assigns = assign(assigns, :flash, flash)

    ~H"""
    <div id="flash-group" phx-hook="FlashHandler">
      <sl-alert
        :for={f <- @flash}
        id={"flash-#{f.id}"}
        variant={f.variant}
        duration={f.duration}
        closable={f.closable}
        countdown={f.countdown}
      >
        <sl-icon slot="icon" name={f.icon} />
        {f.message}
      </sl-alert>
    </div>

    <sl-alert id={"flash-#{Ecto.UUID.generate()}"} phx-hook="DisconnectedHandler" variant="warning">
      <sl-icon slot="icon" name="exclamation-octagon" />
      {gettext("Disconnected from server. Reconnecting...")}
    </sl-alert>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method)
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{"primary" => "btn-primary", nil => "btn-primary btn-soft"}
    assigns = assign(assigns, :class, Map.fetch!(variants, assigns[:variant]))

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={["btn", @class]} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={["btn", @class]} {@rest}>
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
  for more information. Unsupported types, such as hidden and radio,
  are best written directly in your templates.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
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
               range search select tel text textarea time url week radio-card)

  attr :style, :string,
    default: "default",
    values: ~w(default button-addon)

  attr :field, Phoenix.HTML.FormField, doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :string, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :string, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global, include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  slot :inner_block

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
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
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
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
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
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
          {@rest}
        />
      </label>
      <button class="btn btn-primary join-item z-50">{@button_text}</button>
    </fieldset>
    <.error :for={msg <- @errors}>{msg}</.error>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <fieldset class={@hidden && "hidden"}>
      <label class="flex flex-col">
        <span :if={@label} class="mb-1">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[@class || "input input-lg w-full", @errors != [] && (@error_class || "input-error")]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
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
  attr :class, :string, default: nil

  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4", @class]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-base-content/70 text-sm">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc ~S"""
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
            <span class="sr-only">{gettext("Actions")}</span>
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
        <div>
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
  attr :class, :string, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  attr :size, :integer, default: 5

  def social_media_links(assigns) do
    ~H"""
    <div class="flex flex-row gap-4">
      <a href="#">
        <img class={"h-#{@size} w-#{@size}"} src="/images/facebook_logo_bw_128px.png" alt="Facebook logo" />
      </a>
      <a href="#">
        <img class={"h-#{@size} w-#{@size}"} src="/images/instagram_logo_bw_128px.png" alt="Instagram logo" />
      </a>
    </div>
    """
  end

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
  attr :class, :string, default: "bg-white min-w-96"
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
        |> JS.toggle_class("overflow-hidden", to: "html")
      }
      phx-hide={
        %JS{}
        |> JS.hide(to: "##{@id}-backdrop", transition: {@transition, "opacity-100", "opacity-0"}, time: @time)
        |> JS.hide(
          to: "##{@id}-dialog",
          transition: {@transition, @transition_in, @transition_out},
          time: @time
        )
        |> JS.toggle_class("overflow-hidden", to: "html")
      }
      class="z-100 relative"
    >
      <div id={"#{@id}-backdrop"} class="bg-black/30 fixed inset-0 hidden"></div>
      <div
        id={"#{@id}-dialog"}
        role="dialog"
        aria-modal="true"
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
