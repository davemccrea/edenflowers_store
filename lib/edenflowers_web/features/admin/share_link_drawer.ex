defmodule EdenflowersWeb.Admin.ShareLinkDrawer do
  @moduledoc """
  The drawer behind a Share link button, for building a shop link with UTM
  tags before Jennie posts it, so Umami can tell which post or newsletter
  brought each visitor and their order. The path has no language, so each
  visitor lands on the page in their own.

  Copying the link remembers its tags (`Edenflowers.Marketing.TrackingTag`),
  and the fields offer them again next time.

  Render it outside any form, since it has its own, with `id`, `path` (the shop
  page without a language, e.g. /product/:id) and `current_user`. Put
  `open_button/1` where Jennie should find it, such as the page header.
  """

  use EdenflowersWeb, {:live_component, gettext_domain: "admin"}

  import EdenflowersWeb.Admin.Drawers

  alias Edenflowers.Marketing

  attr :id, :string, required: true, doc: "the drawer's id"

  @doc "Opens the share link drawer `id`."
  def open_button(assigns) do
    ~H"""
    <.button
      id={"#{@id}-open"}
      type="button"
      phx-click={JS.exec("phx-show", to: "##{@id}")}
      variant="secondary"
      size="sm"
      class="max-md:btn-square"
    >
      <.icon name="hero-link" class="h-4 w-4" />
      <span class="max-md:sr-only">{~t"Share link"}</span>
    </.button>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    # The parent re-renders on every keystroke in its own form; set up once.
    if socket.assigns[:form] do
      {:ok, socket}
    else
      {:ok, socket |> assign_tags(%{}) |> assign_suggestions()}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.admin_drawer id={@id} title={~t"Share link"}>
        <.form
          for={@form}
          id={"#{@id}-form"}
          phx-change="change"
          phx-target={@myself}
          class="flex min-h-0 flex-1 flex-col"
        >
          <.drawer_body>
            <p class="text-base-content/75 text-sm">
              {~t"Tags tell Umami where a visitor came from, so you can see which posts bring orders. Leave them empty for a plain link."}
            </p>
            <div :for={{parameter, label, hint} <- fields()} class="space-y-1">
              <.input
                field={@form[parameter]}
                label={label}
                validate_live?
                autocomplete="off"
                autocapitalize="none"
                maxlength="100"
                class="input w-full"
              />
              <p class="text-base-content/60 text-xs">{hint}</p>
              <div
                :if={@suggestions[parameter] != []}
                id={"#{@id}-#{parameter}-suggestions"}
                role="group"
                aria-label={label}
                class="flex flex-wrap gap-1.5 pt-1"
              >
                <span
                  :for={value <- @suggestions[parameter]}
                  class="border-base-content/15 inline-flex items-center rounded-full border"
                >
                  <button
                    type="button"
                    phx-click="pick"
                    phx-value-parameter={parameter}
                    phx-value-tag={value}
                    phx-target={@myself}
                    aria-pressed={to_string(chosen?(@form, parameter, value))}
                    class="btn btn-xs btn-ghost rounded-full font-normal shadow-none aria-pressed:btn-primary pointer-coarse:btn-sm"
                  >
                    {value}
                  </button>
                  <button
                    type="button"
                    phx-click="forget"
                    phx-value-parameter={parameter}
                    phx-value-tag={value}
                    phx-target={@myself}
                    aria-label={~t"Remove #{tag = value} from suggestions"}
                    title={~t"Remove from suggestions"}
                    class="btn btn-xs btn-ghost btn-circle text-base-content/60 -ml-1 shadow-none pointer-coarse:btn-sm hover:text-base-content"
                  >
                    <.icon name="hero-x-mark" class="h-3 w-3" />
                  </button>
                </span>
              </div>
            </div>
            <div class="space-y-1">
              <p class="text-sm font-medium">{~t"Link"}</p>
              <input type="hidden" id={"#{@id}-url"} value={@url} />
              <p id={"#{@id}-preview"} class="bg-base-200 rounded-box font-mono break-all p-3 text-xs">{@url}</p>
            </div>
          </.drawer_body>
          <.drawer_footer>
            <.button
              id={"#{@id}-copy"}
              type="button"
              phx-click={
                JS.dispatch("edenflowers:copy", to: "##{@id}-url", detail: %{trigger: "##{@id}-copy"})
                |> JS.push("copied", target: @myself)
              }
              variant="primary"
              class="group"
            >
              <.icon name="hero-clipboard" class="h-4 w-4 group-data-copied:hidden" />
              <.icon name="hero-check" class="hidden h-4 w-4 group-data-copied:inline-block" />
              {~t"Copy link"}
              <span class="sr-only" aria-live="polite">
                <span class="hidden group-data-copied:inline">{~t"Copied"}</span>
              </span>
            </.button>
          </.drawer_footer>
        </.form>
      </.admin_drawer>
    </div>
    """
  end

  @impl true
  def handle_event("change", %{"tags" => params}, socket) do
    {:noreply, assign_tags(socket, params)}
  end

  # Tapping the chosen chip again clears the field, as its aria-pressed promises.
  def handle_event("pick", %{"parameter" => parameter, "tag" => value}, socket) do
    params = socket.assigns.form.params
    value = if chosen?(socket.assigns.form, String.to_existing_atom(parameter), value), do: "", else: value

    {:noreply, assign_tags(socket, Map.put(params, parameter, value))}
  end

  def handle_event("forget", %{"parameter" => parameter, "tag" => value}, socket) do
    Marketing.forget_tracking_tag!(parameter, value, actor: socket.assigns.current_user)

    {:noreply, assign_suggestions(socket)}
  end

  def handle_event("copied", _params, socket) do
    Marketing.use_tracking_tags!(tags(socket.assigns.form), actor: socket.assigns.current_user)

    {:noreply, assign_suggestions(socket)}
  end

  defp assign_tags(socket, params) do
    form = to_form(params, as: :tags)
    url = EdenflowersWeb.Endpoint.url() <> socket.assigns.path

    assign(socket,
      form: form,
      url: Marketing.tagged_url!(url, tags(form), actor: socket.assigns.current_user)
    )
  end

  defp chosen?(form, parameter, value) do
    {parameter, value} in Marketing.TrackingTag.filled_in(tags(form))
  end

  defp fields do
    [
      {:source, ~t"Source", ~t"Where you post it, e.g. instagram or newsletter"},
      {:medium, ~t"Medium", ~t"What kind of post, e.g. social, email or print"},
      {:campaign, ~t"Campaign", ~t"Why you're posting, e.g. mothers-day-2026"}
    ]
  end

  defp tags(form) do
    %{source: form.params["source"], medium: form.params["medium"], campaign: form.params["campaign"]}
  end

  defp assign_suggestions(socket) do
    assign(socket, suggestions: Marketing.tracking_tag_suggestions!(actor: socket.assigns.current_user))
  end
end
