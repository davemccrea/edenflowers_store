defmodule Edenflowers.SeedsTest do
  use Edenflowers.DataCase, async: false

  require Ash.Query

  import ExUnit.CaptureIO
  import Mox

  alias Edenflowers.Orders
  alias Edenflowers.Orders.Order

  @moduletag :typst
  @moduletag capture_log: true

  test "dev fixtures seed successfully on an empty database" do
    stub(Edenflowers.External.StripeAPI.Mock, :retrieve_payment_intent, fn _ -> {:error, :not_found} end)

    capture_io(fn -> Code.eval_file("priv/repo/seeds.exs") end)

    assert Ash.count!(Edenflowers.Orders.Order, authorize?: false) > 0
    assert Ash.count!(Edenflowers.Payments.Invoice, authorize?: false) > 0

    karin = preview_order("Karin Öst")
    assert karin.promotion.gift_order.customer_name == "Hanna Järvinen"
    assert Enum.map(karin.pass_it_on_card.placed_orders, & &1.customer_name) == ["Elin Järvinen", "Olle Berg"]

    olle = preview_order("Olle Berg")
    assert olle.fulfillment_status == :cancelled
    assert olle.promotion.gift_order.id == karin.id
    assert [%{customer_name: "Nils Ek"}] = olle.pass_it_on_card.placed_orders

    nils = preview_order("Nils Ek")
    assert nils.promotion.gift_order.id == olle.id
    assert nils.promotion.gift_order.fulfillment_status == :cancelled

    sanna = preview_order("Sanna Holm")
    assert sanna.promotion.kind == :pass_it_on
    assert sanna.promotion.gift_order == nil

    mikael = preview_order("Mikael Lindholm")
    assert mikael.pass_it_on_card.card_status == :not_opened
    assert mikael.pass_it_on_card.placed_orders == []
  end

  defp preview_order(name) do
    order = Order |> Ash.Query.filter(customer_name == ^name) |> Ash.read_one!(authorize?: false)
    Orders.get_order_for_admin!(order.id, authorize?: false)
  end
end
