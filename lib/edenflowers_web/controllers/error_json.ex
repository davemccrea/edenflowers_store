defmodule EdenflowersWeb.ErrorJSON do
  @moduledoc """
  Renders JSON error responses selected by the endpoint for failed requests.
  """

  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
