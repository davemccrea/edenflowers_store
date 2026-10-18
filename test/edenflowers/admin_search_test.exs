defmodule Edenflowers.AdminSearchTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Accounts
  alias Edenflowers.Orders

  setup do
    %{admin: generate(admin_user())}
  end

  defp placed(attrs), do: generate(order([state: :placed, ordered_at: DateTime.utc_now()] ++ attrs))

  describe "searching orders" do
    for {field, value, term} <- [
          {:customer_name, "Ada Lovelace", "LOVELACE"},
          {:order_reference, "R12345", "r123"},
          {:customer_phone_number, "+358401234567", "40123"},
          {:customer_email, "ada@example.com", "ADA@EXAMPLE"},
          {:recipient_name, "Grace Hopper", "hopper"},
          {:delivery_address, "Kyrkvägen 5, Vasa", "KYRKVÄGEN"}
        ] do
      test "matches #{field} whatever the case", %{admin: admin} do
        order = placed([{unquote(field), unquote(value)}])
        placed([])

        assert [%{id: id}] = Orders.search_orders!(unquote(term), actor: admin)
        assert id == order.id
      end
    end

    test "finds only placed orders", %{admin: admin} do
      generate(order(customer_name: "Ada Lovelace"))

      assert Orders.search_orders!("ada", actor: admin) == []
    end

    test "returns no more than the limit", %{admin: admin} do
      for _ <- 1..3, do: placed(customer_name: "Ada Lovelace")

      assert length(Orders.search_orders!("ada", actor: admin, query: [limit: 2])) == 2
    end
  end

  describe "searching customers" do
    setup do
      ada = generate(admin_user(admin: false, name: "Ada Byron", email: "ada@example.com"))
      placed(user_id: ada.id)
      %{ada: ada}
    end

    test "matches name or email whatever the case", %{admin: admin, ada: ada} do
      assert [%{id: id}] = Accounts.search_customers!("BYRON", actor: admin)
      assert id == ada.id
      assert [%{id: ^id}] = Accounts.search_customers!("ADA@EXAMPLE", actor: admin)
    end

    test "finds only people who have placed an order", %{admin: admin} do
      generate(admin_user(admin: false, name: "Grace Byron"))

      assert [_ada] = Accounts.search_customers!("byron", actor: admin)
    end

    test "returns no more than the limit", %{admin: admin} do
      for _ <- 1..2, do: placed(user_id: generate(admin_user(admin: false, name: "Ada Byron")).id)

      assert length(Accounts.search_customers!("byron", actor: admin, query: [limit: 2])) == 2
    end
  end
end
