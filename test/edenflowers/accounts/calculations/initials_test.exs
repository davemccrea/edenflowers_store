defmodule Edenflowers.Accounts.Calculations.InitialsTest do
  use Edenflowers.DataCase, async: true

  alias Edenflowers.Accounts
  alias Edenflowers.Accounts.Calculations.Initials

  describe "calculate/3 extraction" do
    test "uses the first and final tokens, one initial for a mononym, nil for blank names" do
      assert ["JD"] = calc([%{name: "Jane Doe"}])
      assert ["JS"] = calc([%{name: "Smith, Jane"}])
      assert ["JD"] = calc([%{name: "Jane Mary Doe"}])
      assert ["M"] = calc([%{name: "Madonna"}])
      assert [nil, nil, nil] = calc([%{name: nil}, %{name: ""}, %{name: "   "}])
    end
  end

  test "User.initials extracts initials from User.name" do
    {:ok, user} = Accounts.upsert_user("jane@example.com", "Jane Doe", authorize?: false)
    user = Ash.load!(user, [:initials], authorize?: false)

    assert user.initials == "JD"
  end

  defp calc(records, opts \\ [source: :name]) do
    Initials.calculate(records, opts, %{})
  end
end
