defmodule Edenflowers.Accounts.Calculations.FirstNameTest do
  use Edenflowers.DataCase, async: true
  import Generator

  alias Edenflowers.Accounts.Calculations.FirstName
  alias Edenflowers.Accounts.User

  describe "init/1" do
    test "accepts a :source atom" do
      assert {:ok, opts} = FirstName.init(source: :name)
      assert opts[:source] == :name
    end

    test "rejects when :source is missing" do
      assert {:error, _msg} = FirstName.init([])
    end

    test "rejects when :source is not an atom" do
      assert {:error, _msg} = FirstName.init(source: "name")
    end
  end

  describe "calculate/3 extraction" do
    test "extracts the first token of a 'First Last' name" do
      assert ["Jane"] = calc([%{name: "Jane Doe"}])
    end

    test "returns the given name from a 'Last, First' comma-inverted form" do
      assert ["Jane"] = calc([%{name: "Smith, Jane"}])
    end

    test "trims whitespace around a comma-inverted given name" do
      assert ["Jane"] = calc([%{name: "Smith,   Jane"}])
    end

    test "handles multi-word given name in comma-inverted form by taking the first token" do
      assert ["Mary"] = calc([%{name: "Smith, Mary Anne"}])
    end

    test "collapses multi-word given names to the first token" do
      assert ["Mary"] = calc([%{name: "Mary Anne Smith"}])
    end

    test "treats a mononym as the first name" do
      assert ["Madonna"] = calc([%{name: "Madonna"}])
    end

    test "preserves casing — does not titlecase or downcase" do
      assert ["jane"] = calc([%{name: "  jane  "}])
      assert ["JANE"] = calc([%{name: "JANE DOE"}])
    end

    test "tolerates repeated internal whitespace" do
      assert ["Jane"] = calc([%{name: "Jane     Doe"}])
    end

    test "tolerates tabs and mixed whitespace" do
      assert ["Jane"] = calc([%{name: "\tJane\tDoe\t"}])
    end

    test "returns nil for nil input" do
      assert [nil] = calc([%{name: nil}])
    end

    test "returns nil for an empty string" do
      assert [nil] = calc([%{name: ""}])
    end

    test "returns nil for a whitespace-only string" do
      assert [nil] = calc([%{name: "     "}])
    end

    test "operates on the field named by :source" do
      records = [%{customer_name: "Jane Doe"}, %{customer_name: "Madonna"}]
      assert ["Jane", "Madonna"] = FirstName.calculate(records, [source: :customer_name], %{})
    end

    test "preserves record ordering across a batch" do
      records = [
        %{name: "Alice Adams"},
        %{name: nil},
        %{name: "Smith, Bob"},
        %{name: "Carol"}
      ]

      assert ["Alice", nil, "Bob", "Carol"] = FirstName.calculate(records, [source: :name], %{})
    end
  end

  describe "load/3" do
    test "declares the source attribute as a dependency" do
      assert FirstName.load(nil, [source: :name], %{}) == [:name]
      assert FirstName.load(nil, [source: :customer_name], %{}) == [:customer_name]
    end
  end

  describe "User.first_name calculation" do
    test "extracts first name from User.name" do
      {:ok, user} = User.upsert("jane@example.com", "Jane Doe", authorize?: false)
      user = Ash.load!(user, [:first_name], authorize?: false)

      assert user.first_name == "Jane"
    end

    test "returns nil when User.name is nil" do
      {:ok, user} = User.upsert("noname@example.com", nil, authorize?: false)
      user = Ash.load!(user, [:first_name], authorize?: false)

      assert is_nil(user.first_name)
    end

    test "handles comma-inverted names on User" do
      {:ok, user} = User.upsert("smith@example.com", "Smith, Jane", authorize?: false)
      user = Ash.load!(user, [:first_name], authorize?: false)

      assert user.first_name == "Jane"
    end

    test "handles mononyms on User" do
      {:ok, user} = User.upsert("madonna@example.com", "Madonna", authorize?: false)
      user = Ash.load!(user, [:first_name], authorize?: false)

      assert user.first_name == "Madonna"
    end
  end

  describe "Order.customer_first_name calculation" do
    test "extracts first name from Order.customer_name" do
      order = generate(order(customer_name: "Jane Doe"))
      order = Ash.load!(order, [:customer_first_name], authorize?: false)

      assert order.customer_first_name == "Jane"
    end

    test "returns nil when Order.customer_name is nil" do
      order = generate(order(customer_name: nil))
      order = Ash.load!(order, [:customer_first_name], authorize?: false)

      assert is_nil(order.customer_first_name)
    end

    test "handles comma-inverted customer_name" do
      order = generate(order(customer_name: "Smith, Jane"))
      order = Ash.load!(order, [:customer_first_name], authorize?: false)

      assert order.customer_first_name == "Jane"
    end

    test "reads from customer_name independently of the linked User.name" do
      # customer_name is a per-order snapshot, so even when a user is linked
      # with a different name the calculation should reflect what the order
      # stored at checkout time.
      {:ok, user} = User.upsert("snap@example.com", "Different User Name", authorize?: false)
      order = generate(order(user_id: user.id, customer_name: "Snapshot Name"))

      order = Ash.load!(order, [:customer_first_name], authorize?: false)
      assert order.customer_first_name == "Snapshot"
    end
  end

  defp calc(records, opts \\ [source: :name]) do
    FirstName.calculate(records, opts, %{})
  end
end
