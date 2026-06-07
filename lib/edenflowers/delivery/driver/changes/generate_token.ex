defmodule Edenflowers.Delivery.Driver.Changes.GenerateToken do
  @moduledoc """
  Generates a fresh, unguessable `link_token` for a driver's `/d/:token` page.

  Used on creation and on regeneration; regenerating invalidates the previously
  shared link. ~128 bits of entropy, URL-safe so it drops straight into a path.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.force_change_attribute(changeset, :link_token, generate())
  end

  def generate do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
