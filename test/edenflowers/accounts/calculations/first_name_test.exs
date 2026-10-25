defmodule Edenflowers.Accounts.Calculations.FirstNameTest do
  use Edenflowers.DataCase, async: true
  import Generator

  alias Edenflowers.Accounts
  alias Edenflowers.Accounts.Calculations.FirstName

  describe "calculate/3 extraction" do
    test "extracts the first token of a name, including the comma-inverted form" do
      assert ["Jane"] = calc([%{name: "Jane Doe"}])
      assert ["Jane"] = calc([%{name: "Smith,   Jane"}])
      assert ["Mary"] = calc([%{name: "Mary Anne Smith"}])
      assert ["Madonna"] = calc([%{name: "Madonna"}])
    end

    test "tolerates whitespace and preserves casing" do
      assert ["Jane"] = calc([%{name: "\tJane     Doe\t"}])
      assert ["jane"] = calc([%{name: "  jane  "}])
      assert ["JANE"] = calc([%{name: "JANE DOE"}])
    end

    test "returns nil for a blank name" do
      assert [nil, nil, nil] = calc([%{name: nil}, %{name: ""}, %{name: "     "}])
    end

    test "operates on the field named by :source and preserves record order" do
      records = [%{customer_name: "Jane Doe"}, %{customer_name: nil}, %{customer_name: "Smith, Bob"}]

      assert ["Jane", nil, "Bob"] = FirstName.calculate(records, [source: :customer_name], %{})
    end
  end

  describe "the first_name calculation" do
    test "extracts the first name from User.name" do
      {:ok, user} = Accounts.upsert_user("jane@example.com", "Jane Doe", authorize?: false)
      user = Ash.load!(user, [:first_name], authorize?: false)

      assert user.first_name == "Jane"
    end

    test "Order.customer_first_name reads the order's own snapshot, not the linked User" do
      {:ok, user} = Accounts.upsert_user("snap@example.com", "Different User Name", authorize?: false)
      order = generate(order(user_id: user.id, customer_name: "Snapshot Name"))

      order = Ash.load!(order, [:customer_first_name], authorize?: false)

      assert order.customer_first_name == "Snapshot"
    end
  end

  defp calc(records, opts \\ [source: :name]) do
    FirstName.calculate(records, opts, %{})
  end
end
