defmodule EdenflowersWeb.Admin.GiftVoucherSaleLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    %{conn: log_in(conn, generate(admin_user()) |> with_token())}
  end

  test "Jennie sells a voucher and lands on its order, with the code to copy", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/orders/new-gift-voucher")

    refute has_element?(view, ~s|input[name="form[email_recipient?]"][type=checkbox]|)

    view
    |> form("#gift-voucher-form", form: %{customer_name: "Anna Holm", recipient_email: "maria@example.com"})
    |> render_change()

    assert has_element?(view, ~s|input[name="form[email_recipient?]"][type=checkbox]|)

    {:error, {:live_redirect, %{to: path}}} =
      view
      |> form("#gift-voucher-form",
        form: %{
          customer_name: "Anna Holm",
          customer_email: "anna@example.com",
          recipient_name: "Maria Lind",
          amount: "35"
        }
      )
      |> render_submit()

    {:ok, order_view, html} = live(conn, path)
    assert html =~ "Maria Lind"
    assert html =~ "Sold in the shop"
    # A pass-it-on card goes out with flowers, and a voucher sale has none.
    refute has_element?(order_view, "#order-pass-it-on")
  end

  test "finds an existing customer, fills in their details and sells to them", %{conn: conn} do
    customer = generate(admin_user(admin: false, name: "Anna Holm", email: "anna@example.com"))

    generate(
      order(
        state: :placed,
        user_id: customer.id,
        customer_phone_number: "+358401234567",
        ordered_at: DateTime.utc_now()
      )
    )

    {:ok, view, _html} = live(conn, ~p"/admin/orders/new-gift-voucher")

    # Clicking into the empty search lists the latest customers, as on the invoice page.
    view |> element("#customer-select") |> render_hook("focus", %{})
    render_hook(view, "customer_focus", %{"id" => "customer-select"})
    render(view)
    assert has_element?(view, "#customer-select ul", "anna@example.com")

    view |> element("#form_customer_id_text_input") |> render_change(%{"text" => "anna"})
    render_hook(view, "live_select_change", %{"id" => "customer-select", "text" => "anna"})
    assert has_element?(view, "#customer-select ul", "anna@example.com")
    view |> element("#customer-select") |> render_hook("option_click", %{"idx" => "0"})

    view |> form("#gift-voucher-form", form: %{customer_id: customer.id}) |> render_change()

    assert has_element?(view, ~s|#form_customer_name[value="Anna Holm"]|)
    assert has_element?(view, ~s|#form_customer_email[value="anna@example.com"]|)
    assert has_element?(view, ~s|#form_customer_phone_number[value="040 1234567"]|)

    {:error, {:live_redirect, %{to: "/admin/orders/" <> id}}} =
      view |> form("#gift-voucher-form", form: %{customer_id: customer.id, amount: "50"}) |> render_submit()

    assert Edenflowers.Orders.get_order_for_admin!(id, authorize?: false).user_id == customer.id
  end

  test "says what's missing instead of selling", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/orders/new-gift-voucher")

    html = view |> form("#gift-voucher-form", form: %{customer_name: "Anna Holm", amount: "10"}) |> render_submit()

    assert html =~ "The voucher wasn&#39;t sold."
  end
end
