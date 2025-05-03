defmodule Edenflowers.Emails do
  import Swoosh.Email
  use Gettext, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Store.Order

  def order_confirmation(%Order{} = order) do
    new()
    |> to({order.customer_name, order.customer_email})
    |> from({"Jennie", "info@edenflowers.fi"})
    |> subject(gettext("Thank you for your order"))
    |> text_body("Testing testing")
  end
end
