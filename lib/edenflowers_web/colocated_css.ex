defmodule EdenflowersWeb.ColocatedCSS do
  @moduledoc """
  Extracts colocated styles into the application's CSS bundle without changing
  their selectors. Components should use feature-specific classes or IDs; some
  rules deliberately reach outside the component, such as the voucher preview
  hiding the site header while it occupies the top of the viewport.
  """

  use Phoenix.LiveView.ColocatedCSS

  @impl true
  def transform("style", _attrs, css, _meta), do: {:ok, css, []}
end
