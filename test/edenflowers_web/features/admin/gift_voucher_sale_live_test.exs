defmodule EdenflowersWeb.Admin.GiftVoucherSaleLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    %{conn: log_in(conn, generate(admin_user()) |> with_token())}
  end

  test "Jennie sells a voucher paid in cash and lands on its order, with the code to copy", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/orders/new-gift-voucher")

    refute has_element?(view, ~s|input[name="form[email_buyer?]"][type=checkbox]|)

    view
    |> form("#gift-voucher-form", form: %{customer_name: "Anna Holm", customer_email: "anna@example.com"})
    |> render_change()

    assert has_element?(view, ~s|input[name="form[email_buyer?]"][type=checkbox]|)
    refute has_element?(view, ~s|input[name="form[email_recipient?]"][type=checkbox]|)

    {:error, {:live_redirect, %{to: path}}} =
      view
      |> form("#gift-voucher-form",
        form: %{
          customer_name: "Anna Holm",
          customer_email: "anna@example.com",
          recipient_name: "Maria Lind",
          amount: "35",
          payment_method: "cash"
        }
      )
      |> render_submit()

    {:ok, order_view, html} = live(conn, path)
    assert html =~ "Maria Lind"
    assert html =~ "Sold in the shop"
    # A pass-it-on card goes out with flowers, and a voucher sale has none.
    refute has_element?(order_view, "#order-pass-it-on")
  end

  test "says what's missing instead of selling", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/orders/new-gift-voucher")

    html = view |> form("#gift-voucher-form", form: %{customer_name: "Anna Holm", amount: "10"}) |> render_submit()

    assert html =~ "The voucher wasn&#39;t sold."
  end
end
