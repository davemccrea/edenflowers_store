defmodule EdenflowersWeb.Admin.SlugField do
  @moduledoc """
  The Link input of the product and course forms, for the slug the page lives
  at, with the full URL beneath it as it will be saved.

  On a new record the link follows the name until Jennie edits the link
  herself. A LiveView wires that up by keeping a `slug_edited?` assign, false on
  mount, and passing its validate params through `suggest/3`:

      slug_edited? = socket.assigns.slug_edited? or SlugField.edited?(event)
      params = SlugField.suggest(params, socket.assigns.form, slug_edited?)
  """
  use EdenflowersWeb, {:html, gettext_domain: "admin"}

  alias Edenflowers.Slug

  attr :field, Phoenix.HTML.FormField, required: true
  attr :path, :string, required: true, doc: "The page's path before the slug, like /product/"

  def slug_field(assigns) do
    ~H"""
    <.input
      field={@field}
      type="text"
      label={~t"Link"}
      help={url_preview(@path, @field.value)}
      autocomplete="off"
      class="input w-full"
    />
    """
  end

  def edited?(event), do: event["_target"] == ["form", "slug"]

  def suggest(params, %{source: %{type: :create}}, false = _slug_edited?),
    do: Map.put(params, "slug", Slug.slugify(params["name"]))

  def suggest(params, _form, _slug_edited?), do: params

  defp url_preview(path, slug) do
    URI.parse(EdenflowersWeb.Endpoint.url()).host <> path <> Slug.slugify(slug)
  end
end
