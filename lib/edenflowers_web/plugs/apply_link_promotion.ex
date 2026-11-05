defmodule EdenflowersWeb.Plugs.ApplyLinkPromotion do
  @moduledoc """
  Puts the promo code from a storefront link's `?code=` on the browser's cart, so a QR code or a post's link
  saves typing it. Runs after `InitStore`, which gives the browser its visitor_id.
  """

  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "storefront"]

  import Phoenix.Controller, only: [put_flash: 3]
  import Plug.Conn

  alias Edenflowers.Orders

  def init(opts), do: opts

  def call(%{params: %{"code" => code}} = conn, _opts) when is_binary(code) and code != "" do
    visitor_id = get_session(conn, :visitor_id)

    case Orders.open_cart_with_code(visitor_id, code, actor: conn.assigns[:current_user]) do
      {:ok, true} ->
        code = code |> String.trim() |> String.upcase()
        put_flash(conn, :success, ~t"Promo code #{code} is in your cart.")

      _not_applied ->
        conn
    end
  end

  def call(conn, _opts), do: conn
end
