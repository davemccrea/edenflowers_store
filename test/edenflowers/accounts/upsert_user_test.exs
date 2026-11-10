defmodule Edenflowers.Accounts.UpsertUserTest do
  use Edenflowers.DataCase, async: true

  alias Edenflowers.Accounts

  # The email is typed by a guest and never verified, so it can't rename the account behind it.
  test "a later upsert keeps an existing name but fills a missing one" do
    {:ok, named} = Accounts.upsert_user("named@example.com", "Maria Virtanen", authorize?: false)
    {:ok, again} = Accounts.upsert_user("NAMED@example.com", "Someone Else", authorize?: false)

    assert again.id == named.id
    assert again.name == "Maria Virtanen"
    assert to_string(again.email) == "named@example.com"

    {:ok, nameless} = Accounts.upsert_user("nameless@example.com", nil, authorize?: false)
    {:ok, filled} = Accounts.upsert_user("nameless@example.com", "Anna Lind", authorize?: false)

    assert filled.id == nameless.id
    assert filled.name == "Anna Lind"
  end
end
