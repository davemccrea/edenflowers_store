defmodule Edenflowers.Accounts.Calculations.InitialsTest do
  use Edenflowers.DataCase, async: true

  alias Edenflowers.Accounts.Calculations.Initials
  alias Edenflowers.Accounts.User

  describe "calculate/3 extraction" do
    test "uses first and last initials for a regular full name" do
      assert ["JD"] = calc([%{name: "Jane Doe"}])
    end

    test "uses given and family initials for comma-inverted names" do
      assert ["JS"] = calc([%{name: "Smith, Jane"}])
    end

    test "uses the first and final tokens for multi-part names" do
      assert ["JD"] = calc([%{name: "Jane Mary Doe"}])
    end

    test "returns one initial for a mononym" do
      assert ["M"] = calc([%{name: "Madonna"}])
    end

    test "returns nil for blank names" do
      assert [nil, nil, nil] = calc([%{name: nil}, %{name: ""}, %{name: "   "}])
    end
  end

  describe "load/3" do
    test "declares the source attribute as a dependency" do
      assert Initials.load(nil, [source: :name], %{}) == [:name]
    end
  end

  describe "User.initials calculation" do
    test "extracts initials from User.name" do
      {:ok, user} = User.upsert("jane@example.com", "Jane Doe", authorize?: false)
      user = Ash.load!(user, [:initials], authorize?: false)

      assert user.initials == "JD"
    end
  end

  defp calc(records, opts \\ [source: :name]) do
    Initials.calculate(records, opts, %{})
  end
end
