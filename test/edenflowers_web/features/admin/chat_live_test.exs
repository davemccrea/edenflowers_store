defmodule EdenflowersWeb.Admin.ChatLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator

  alias AshAuthentication.Plug.Helpers

  test "deletes a conversation along with its messages", %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    conn = conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(admin)

    conversation = Edenflowers.Chat.create_conversation!(%{title: "Weekend orders"}, actor: admin)

    # Seeded so the create action's Oban trigger doesn't ask the model for a reply.
    Ash.Seed.seed!(Edenflowers.Chat.Message, %{
      conversation_id: conversation.id,
      text: "What needs delivering on Saturday?",
      source: :user
    })

    {:ok, view, _html} = live(conn, ~p"/admin/chat/#{conversation.id}")
    view |> element("button", "Delete") |> render_click()

    assert_patch(view, ~p"/admin/chat")
    refute render(view) =~ "Weekend orders"
    assert Edenflowers.Chat.my_conversations!(actor: admin) == []
  end
end
