defmodule Edenflowers.Accounts.Calculations.NamePartTest do
  use Edenflowers.DataCase, async: true
  import Generator

  alias Edenflowers.Accounts
  alias Edenflowers.Accounts.Calculations.NamePart

  test "splits a name into its first word and the rest, keeping their casing" do
    assert calc(:first, ["Jane Doe", "\tjane   doe ", "Madonna", nil, "   "]) == ["Jane", "jane", "Madonna", nil, nil]
    assert calc(:last, ["Jane Doe", "  Jan   van der Berg ", "Madonna", nil]) == ["Doe", "van der Berg", nil, nil]
  end

  test "initials come from the first and last words, or the fallback when there's no name" do
    records = [%{name: "mary anne smith", email: "m@x"}, %{name: "Madonna", email: "m@x"}, %{name: nil, email: "jo@x"}]

    assert NamePart.calculate(records, [source: :name, part: :initials, fallback: :email], %{}) == ["MS", "M", "J"]
    assert NamePart.calculate([%{name: nil}], [source: :name, part: :initials], %{}) == [nil]
  end

  test "Order.customer_first_name reads the order's own snapshot, not the linked User" do
    {:ok, user} = Accounts.upsert_user("snap@example.com", "Different User Name", authorize?: false)
    order = generate(order(user_id: user.id, customer_name: "Snapshot Name"))

    assert Ash.load!(order, :customer_first_name, authorize?: false).customer_first_name == "Snapshot"
  end

  defp calc(part, names),
    do: NamePart.calculate(Enum.map(names, &%{name: &1}), [source: :name, part: part], %{})
end
