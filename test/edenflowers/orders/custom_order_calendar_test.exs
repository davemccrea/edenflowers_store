defmodule Edenflowers.Orders.CustomOrderCalendarTest do
  use Edenflowers.DataCase, async: false

  import Generator

  alias Edenflowers.Orders

  describe "placing a custom order" do
    test "may be booked on a closed day, but never in the past" do
      admin = generate(admin_user())
      tax_rate = generate(tax_rate(percentage: "0.255"))
      product = generate(product(tax_rate_id: tax_rate.id, name: "Spring Bouquet"))
      variant = generate(product_variant(product_id: product.id, price: "49.00"))

      pickup =
        generate(fulfillment_option(tax_rate_id: tax_rate.id, fulfillment_method: :pickup, base_price: "0.00"))

      tomorrow = Date.add(Edenflowers.ShopTime.today(), 1)

      params = %{
        customer_name: "Mrs Holm",
        customer_phone_number: "040 123 4567",
        locale: "sv-FI",
        fulfillment_option_id: pickup.id,
        fulfillment_date: tomorrow,
        line_items: [
          %{"kind" => "catalogue", "product_variant_id" => variant.id, "quantity" => "1"},
          %{
            "kind" => "custom",
            "product_name" => "Funeral spray",
            "unit_price" => "85,00",
            "tax_rate_id" => tax_rate.id,
            "quantity" => "1"
          }
        ]
      }

      shop_calendar(available_days: [])

      assert {:ok, _order} = Orders.place_custom_order(params, actor: admin)

      assert {:error, error} =
               Orders.place_custom_order(%{params | fulfillment_date: Date.add(tomorrow, -2)}, actor: admin)

      assert Exception.message(error) =~ "cannot be in the past"
    end
  end
end
