defmodule EdenflowersWeb.PaymentLink do
  @moduledoc "The URL a customer opens to pay a custom order online."
  use EdenflowersWeb, :verified_routes

  def url_for(%{payment_link_token: token}) when is_binary(token), do: url(~p"/pay/#{token}")
end
