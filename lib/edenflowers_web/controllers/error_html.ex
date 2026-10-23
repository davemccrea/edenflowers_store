defmodule EdenflowersWeb.ErrorHTML do
  @moduledoc """
  Renders the HTML error pages selected by the endpoint for failed requests.
  """
  use EdenflowersWeb, :html

  embed_templates "error_html/*"

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
