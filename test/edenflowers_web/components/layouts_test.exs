defmodule EdenflowersWeb.LayoutsTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias EdenflowersWeb.Layouts

  test "admin sidebar renders locale pickers for mobile and desktop" do
    html =
      render_component(&Layouts.admin/1,
        flash: %{},
        current_path: "/admin/orders",
        current_user: %{email: "admin@example.com", first_name: "Admin", initials: "A"},
        inner_block: []
      )

    assert html =~ ~s(id="admin-locale-picker-mobile")
    assert html =~ ~s(id="admin-locale-picker-desktop")

    for locale <- Edenflowers.Locales.all() do
      assert html =~ "/locale/#{locale}?redirect_to=%2Fadmin%2Forders"
    end
  end
end
