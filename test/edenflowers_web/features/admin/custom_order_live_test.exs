defmodule EdenflowersWeb.Admin.CustomOrderLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Mox
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders

  setup :verify_on_exit!

  setup %{conn: conn} do
    admin = generate(admin_user()) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(admin)

    tax_rate = generate(tax_rate(name: "Flowers"))
    product = generate(product(tax_rate_id: tax_rate.id, name: "Spring Bouquet"))
    variant = generate(product_variant(product_id: product.id, price: "49.00"))

    pickup =
      generate(fulfillment_option(tax_rate_id: tax_rate.id, name: "Pickup at the shop", base_price: "0.00"))

    %{conn: conn, admin: admin, tax_rate: tax_rate, variant: variant, pickup: pickup}
  end

  defp delivery_option(ctx) do
    generate(
      fulfillment_option(
        tax_rate_id: ctx.tax_rate.id,
        name: "Delivery",
        fulfillment_method: :delivery,
        rate_type: :dynamic,
        base_price: "5.00",
        price_per_km: "1.00",
        free_dist_km: 0,
        max_dist_km: 20
      )
    )
  end

  defp stub_geocoding(distance_m) do
    stub(Edenflowers.External.HereAPI.Mock, :geocode, fn _query ->
      {:ok, {"Kyrkvägen 5, Vasa", "63.09,21.61", "here:1"}}
    end)

    stub(Edenflowers.External.HereAPI.Mock, :route_distance, fn _position -> {:ok, distance_m} end)
  end

  defp tomorrow, do: Date.add(Edenflowers.ShopTime.today(), 1)

  defp search_customers(view, text) do
    view |> element("#form_customer_id_text_input") |> render_change(%{"text" => text})
    render_hook(view, "live_select_change", %{"id" => "customer-select", "text" => text})
    render(view)
  end

  defp select_customer(view, customer, text) do
    search_customers(view, text)
    assert has_element?(view, "#customer-select ul", to_string(customer.email))
    view |> element("#customer-select") |> render_hook("option_click", %{"idx" => "0"})
    assert_push_event(view, "select", %{id: "customer-select", selection: [%{value: selected_id}]})
    assert selected_id == customer.id
    view |> form("#order-form", form: %{customer_id: customer.id}) |> render_change()
  end

  defp place_custom_order(ctx, overrides \\ %{}) do
    {:ok, order} =
      Orders.place_custom_order(
        Map.merge(
          %{
            customer_name: "Mrs Holm",
            customer_phone_number: "040 123 4567",
            fulfillment_option_id: ctx.pickup.id,
            fulfillment_date: tomorrow(),
            locale: "en-GB",
            email_customer?: false,
            line_items: [
              %{
                "kind" => "custom",
                "product_name" => "Funeral spray",
                "unit_price" => "85.00",
                "tax_rate_id" => ctx.tax_rate.id,
                "quantity" => "1"
              }
            ]
          },
          overrides
        ),
        actor: ctx.admin
      )

    order
  end

  describe "placing a custom order" do
    test "auto-recovery keeps the selected customer and order-only contacts, recipient and nested items", ctx do
      customer = generate(admin_user(admin: false, name: "Original Customer", email: "original@example.com"))
      generate(order(state: :placed, user_id: customer.id, customer_phone_number: "+358401234567"))
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/new")
      select_customer(view, customer, "Original")

      recovered = %{
        "customer_id" => customer.id,
        "customer_name" => "Order-only Customer",
        "customer_email" => "order-only@example.com",
        "customer_phone_number" => "040 999 9999",
        "gift" => "true",
        "recipient_name" => "Separate Recipient",
        "recipient_phone_number" => "050 765 4321",
        "fulfillment_option_id" => ctx.pickup.id,
        "fulfillment_date" => Date.to_iso8601(tomorrow()),
        "email_customer?" => "false",
        "line_items" => %{
          "0" => %{
            "_form_type" => "create",
            "kind" => "custom",
            "product_name" => "Recovered bouquet",
            "unit_price" => "35.00",
            "quantity" => "2",
            "tax_rate_id" => ctx.tax_rate.id
          }
        }
      }

      # A fresh mount has no previous customer id or nested forms to compare against.
      {:ok, remounted, _html} = live(ctx.conn, ~p"/admin/orders/new")
      assert has_element?(remounted, ~s|#order-form[phx-auto-recover="recover"]|)
      render_change(remounted, "recover", %{"form" => recovered})

      assert has_element?(remounted, ~s|#form_customer_id[value="#{customer.id}"]|)
      assert has_element?(remounted, ~s|#form_customer_name[value="Order-only Customer"]|)
      assert has_element?(remounted, ~s|#form_customer_email[value="order-only@example.com"]|)
      assert has_element?(remounted, ~s|#form_customer_phone_number[value="040 9999999"]|)
      assert has_element?(remounted, ~s|#form_recipient_name[value="Separate Recipient"]|)
      assert has_element?(remounted, ~s|#form_recipient_phone_number[value="050 7654321"]|)
      assert has_element?(remounted, ~s|#form_line_items_0_product_name[value="Recovered bouquet"]|)
      assert has_element?(remounted, ~s|#form_line_items_0_quantity[value="2"]|)

      remounted |> form("#order-form", form: %{florist_note: "After recovery"}) |> render_change()
      assert has_element?(remounted, ~s|#form_customer_name[value="Order-only Customer"]|)

      assert {:error, {:live_redirect, %{to: "/admin/orders/" <> id}}} =
               remounted |> form("#order-form") |> render_submit()

      order = Orders.get_order_for_admin!(id, actor: ctx.admin, load: [:line_items])
      assert order.user_id == customer.id
      assert order.customer_name == "Order-only Customer"
      assert to_string(order.customer_email) == "order-only@example.com"
      assert order.customer_phone_number == "040 9999999"
      assert order.recipient_name == "Separate Recipient"
      assert order.recipient_phone_number == "050 7654321"
      assert [%{product_name: "Recovered bouquet", quantity: 2}] = order.line_items
    end

    test "selects with the keyboard and clears the association while retaining editable contact details", ctx do
      customer = generate(admin_user(admin: false, name: "Keyboard Customer", email: "keyboard@example.com"))
      generate(order(state: :placed, user_id: customer.id))
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/new")

      assert has_element?(view, "#customer-search-help", "Search by name or email.")
      search_customers(view, "Keyboard")
      assert has_element?(view, "#customer-select ul", "keyboard@example.com")
      view |> element("#customer-select") |> render_hook("keydown", %{"key" => "ArrowDown"})
      assert has_element?(view, "#customer-select .bg-primary.text-primary-content", "keyboard@example.com")
      view |> element("#customer-select") |> render_hook("keydown", %{"key" => "Enter"})
      assert_push_event(view, "select", %{id: "customer-select", selection: [%{value: selected_id}]})
      assert selected_id == customer.id
      view |> form("#order-form", form: %{customer_id: customer.id}) |> render_change()
      assert has_element?(view, ~s|#form_customer_name[value="Keyboard Customer"]|)
      refute has_element?(view, "#customer-results", "Customer selected.")
      refute render(view) =~ "The order wasn't saved."

      for event <- ["focus", "click"] do
        view |> element("#customer-select") |> render_hook(event)

        assert_push_event(view, "select", %{
          id: "customer-select",
          current_text: "",
          input_event: false,
          selection: [%{value: ^selected_id}]
        })
      end

      view |> element("#form_customer_id_text_input") |> render_blur()

      assert_push_event(view, "select", %{
        id: "customer-select",
        current_text: "Keyboard Customer · keyboard@example.com",
        selection: [%{value: ^selected_id}]
      })

      view |> form("#order-form", form: %{customer_name: "Order-only name"}) |> render_change()
      assert has_element?(view, ~s|#form_customer_name[value="Order-only name"]|)
      view |> element(~s|#customer-select button[phx-click="clear"]|) |> render_click()
      view |> form("#order-form", form: %{customer_id: ""}) |> render_change()
      assert has_element?(view, "#form_customer_id:not([value])")
      assert has_element?(view, ~s|#form_customer_name[value="Order-only name"]|)
      assert has_element?(view, ~s|#form_customer_email[value="keyboard@example.com"]|)
    end

    for change_email? <- [false, true] do
      @change_email? change_email?
      test "selected customer contact edits stay on the order (change email: #{change_email?})", ctx do
        customer = generate(admin_user(admin: false, name: "Anna Holm", email: "anna@example.com"))

        previous =
          generate(
            order(
              state: :placed,
              user_id: customer.id,
              customer_phone_number: "+358401234567",
              ordered_at: DateTime.utc_now()
            )
          )

        {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/new")
        render_click(view, "add_line", %{"kind" => "custom"})
        view |> form("#order-form", form: %{gift: "true"}) |> render_change()

        view
        |> form("#order-form",
          form: %{gift: "true", recipient_name: "Recipient", recipient_phone_number: "050 765 4321"}
        )
        |> render_change()

        select_customer(view, customer, "ANNA")

        assert has_element?(view, ~s|#form_customer_name[value="Anna Holm"]|)
        assert has_element?(view, ~s|#form_customer_email[value="anna@example.com"]|)
        assert has_element?(view, ~s|#form_customer_phone_number[value="040 1234567"]|)
        assert has_element?(view, ~s|#form_recipient_name[value="Recipient"]|)
        assert has_element?(view, ~s|#form_recipient_phone_number[value="050 7654321"]|)
        assert has_element?(view, ~s|input[name="form[line_items][0][product_name]"]|)

        email = if @change_email?, do: "order-only@example.com", else: "anna@example.com"

        assert {:error, {:live_redirect, %{to: "/admin/orders/" <> id}}} =
                 view
                 |> form("#order-form",
                   form: %{
                     customer_name: "Anna Holm-Smith",
                     customer_email: email,
                     customer_phone_number: "040 999 9999",
                     fulfillment_option_id: ctx.pickup.id,
                     fulfillment_date: Date.to_iso8601(tomorrow()),
                     email_customer?: false,
                     line_items: %{
                       "0" => %{"product_name" => "Bouquet", "unit_price" => "35", "tax_rate_id" => ctx.tax_rate.id}
                     }
                   }
                 )
                 |> render_submit()

        order = Orders.get_order_for_admin!(id, actor: ctx.admin)
        assert order.user_id == customer.id
        assert order.customer_name == "Anna Holm-Smith"
        assert to_string(order.customer_email) == email
        assert order.customer_phone_number == "040 9999999"
        assert order.recipient_name == "Recipient"
        assert order.recipient_phone_number == "050 7654321"
        saved_customer = Ash.reload!(customer, actor: ctx.admin)
        assert saved_customer.name == "Anna Holm"
        assert to_string(saved_customer.email) == "anna@example.com"
        assert Ash.reload!(previous, actor: ctx.admin).customer_phone_number == "+358401234567"
      end
    end

    test "searches by email and leaves missing customer details editable, without using a gift recipient's phone",
         ctx do
      customer = generate(admin_user(admin: false, name: nil, email: "returning@example.com"))

      generate(
        order(
          state: :placed,
          user_id: customer.id,
          origin: :online,
          gift: true,
          fulfillment_method: :delivery,
          recipient_phone_number: "+358501112222"
        )
      )

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/new")

      view
      |> form("#order-form", form: %{customer_name: "Old entry", customer_phone_number: "040 111 1111"})
      |> render_change()

      select_customer(view, customer, "returning@")

      assert has_element?(view, ~s|#form_customer_name:not([value])|)
      assert has_element?(view, ~s|#form_customer_phone_number:not([value])|)
      assert has_element?(view, ~s|#form_customer_email[value="returning@example.com"]|)

      render_click(view, "add_line", %{"kind" => "custom"})

      assert {:error, {:live_redirect, %{to: "/admin/orders/" <> id}}} =
               view
               |> form("#order-form",
                 form: %{
                   customer_name: "Returning Customer",
                   customer_phone_number: "040 222 2222",
                   fulfillment_option_id: ctx.pickup.id,
                   fulfillment_date: Date.to_iso8601(tomorrow()),
                   email_customer?: false,
                   line_items: %{
                     "0" => %{"product_name" => "Bouquet", "unit_price" => "35", "tax_rate_id" => ctx.tax_rate.id}
                   }
                 }
               )
               |> render_submit()

      assert Orders.get_order_for_admin!(id, actor: ctx.admin).customer_phone_number == "040 2222222"
      assert Ash.reload!(customer, actor: ctx.admin).name == nil
    end

    test "prefills an online customer's own phone but ignores a newer gift recipient", ctx do
      customer = generate(admin_user(admin: false, name: "Online Customer"))

      generate(
        order(
          state: :placed,
          user_id: customer.id,
          origin: :online,
          gift: false,
          fulfillment_method: :delivery,
          recipient_phone_number: "+358401234567",
          ordered_at: ~U[2026-10-01 12:00:00Z]
        )
      )

      generate(
        order(
          state: :placed,
          user_id: customer.id,
          origin: :online,
          gift: true,
          fulfillment_method: :delivery,
          recipient_phone_number: "+358509999999",
          ordered_at: ~U[2026-10-02 12:00:00Z]
        )
      )

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/new")
      select_customer(view, customer, "Online")
      assert has_element?(view, ~s|#form_customer_phone_number[value="040 1234567"]|)

      search_customers(view, "No match")
      assert has_element?(view, "#customer-results", "No customers found.")
      refute has_element?(view, "#customer-results button")
    end

    test "prefills the buyer's phone from an online gift pickup, ignoring a newer custom gift pickup", ctx do
      customer = generate(admin_user(admin: false, name: "Pickup Customer"))

      generate(
        order(
          state: :placed,
          user_id: customer.id,
          origin: :online,
          gift: true,
          fulfillment_method: :pickup,
          recipient_phone_number: "+358401234567",
          ordered_at: ~U[2026-10-01 12:00:00Z]
        )
      )

      generate(
        order(
          state: :placed,
          user_id: customer.id,
          origin: :custom,
          gift: true,
          fulfillment_method: :pickup,
          recipient_phone_number: "+358509999999",
          ordered_at: ~U[2026-10-02 12:00:00Z]
        )
      )

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/new")
      select_customer(view, customer, "Pickup")
      assert has_element?(view, ~s|#form_customer_phone_number[value="040 1234567"]|)
    end

    test "Jennie enters the order and lands on its page", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/new")

      render_click(view, "add_line", %{"kind" => "catalogue"})
      render_click(view, "add_line", %{"kind" => "custom"})

      assert {:error, {:live_redirect, %{to: "/admin/orders/" <> id}}} =
               view
               |> form("#order-form",
                 form: %{
                   customer_name: "Mrs Holm",
                   customer_phone_number: "040 123 4567",
                   locale: "sv-FI",
                   fulfillment_option_id: ctx.pickup.id,
                   fulfillment_date: Date.to_iso8601(tomorrow()),
                   florist_note: "White only, no lilies",
                   line_items: %{
                     "0" => %{"product_variant_id" => ctx.variant.id, "quantity" => "1"},
                     "1" => %{
                       "product_name" => "Funeral spray",
                       "unit_price" => "85,50",
                       "tax_rate_id" => ctx.tax_rate.id,
                       "quantity" => "1"
                     }
                   }
                 }
               )
               |> render_submit()

      order = Orders.get_order_for_admin!(id, actor: ctx.admin)

      assert order.origin == :custom
      assert order.customer_name == "Mrs Holm"
      assert order.customer_phone_number == "040 1234567"
      assert order.user_id == nil
      assert order.florist_note == "White only, no lilies"
      assert Decimal.equal?(order.grand_total, "134.50")
      assert order.payment_link_open?
    end

    test "ends with the payment choice and one Place order button", ctx do
      {:ok, _view, html} = live(ctx.conn, ~p"/admin/orders/new")

      [form] = html |> LazyHTML.from_document() |> LazyHTML.query("#order-form") |> Enum.to_list()
      sections = form |> LazyHTML.query("section h2") |> Enum.map(&LazyHTML.text/1)
      submits = html |> LazyHTML.from_document() |> LazyHTML.query(~s|button[type="submit"]|) |> Enum.to_list()

      assert List.last(sections) == "Payment"
      assert [submit] = submits
      assert LazyHTML.text(submit) =~ "Place order"
    end

    test "sets an exact time or a window, and the order page and Overview show it", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/new")

      assert has_element?(view, ~s|input[name="form[fulfillment_time]"][value="any"][checked]|)
      refute has_element?(view, ~s|input[name="form[fulfillment_time_start]"]|)

      view |> form("#order-form", form: %{fulfillment_time: "at"}) |> render_change()
      assert has_element?(view, ~s|input[name="form[fulfillment_time_start]"]|)
      refute has_element?(view, ~s|input[name="form[fulfillment_time_end]"]|)

      view |> form("#order-form", form: %{fulfillment_time: "between"}) |> render_change()
      assert has_element?(view, ~s|input[name="form[fulfillment_time_end]"]|)

      render_click(view, "add_line", %{"kind" => "custom"})

      assert {:error, {:live_redirect, %{to: "/admin/orders/" <> id}}} =
               view
               |> form("#order-form",
                 form: %{
                   customer_name: "Mrs Holm",
                   customer_phone_number: "040 123 4567",
                   fulfillment_option_id: ctx.pickup.id,
                   fulfillment_date: Date.to_iso8601(tomorrow()),
                   fulfillment_time: "between",
                   fulfillment_time_start: "14:00",
                   fulfillment_time_end: "15:00",
                   line_items: %{
                     "0" => %{"product_name" => "Wreath", "unit_price" => "85", "tax_rate_id" => ctx.tax_rate.id}
                   }
                 }
               )
               |> render_submit()

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/#{id}")
      assert has_element?(view, "#order-fulfillment-time", "14:00–15:00")

      {:ok, view, _html} = live(ctx.conn, ~p"/admin")
      assert has_element?(view, "[data-testid=fulfillment-time]", "14:00–15:00")

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/#{id}/edit")
      assert has_element?(view, ~s|input[name="form[fulfillment_time]"][value="between"][checked]|)
    end

    test "refuses a window that ends before it starts", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/new")
      view |> form("#order-form", form: %{fulfillment_time: "between"}) |> render_change()

      html =
        view
        |> form("#order-form",
          form: %{fulfillment_time: "between", fulfillment_time_start: "15:00", fulfillment_time_end: "14:00"}
        )
        |> render_submit()

      assert html =~ "Must be after the start"
    end

    test "asks for a recipient and card only for a gift", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/new")

      assert has_element?(view, ~s|input[name="form[gift]"][value="false"][checked]|)
      refute has_element?(view, ~s|input[name="form[recipient_name]"]|)
      refute has_element?(view, ~s|input[name="form[recipient_phone_number]"]|)
      refute has_element?(view, ~s|textarea[name="form[card_message]"]|)

      view |> form("#order-form", form: %{gift: "true"}) |> render_change()

      assert has_element?(view, ~s|input[name="form[recipient_name]"]|)
      assert has_element?(view, ~s|input[name="form[recipient_phone_number]"]|)
      assert has_element?(view, ~s|textarea[name="form[card_message]"]|)

      render_click(view, "add_line", %{"kind" => "custom"})

      assert {:error, {:live_redirect, %{to: "/admin/orders/" <> id}}} =
               view
               |> form("#order-form",
                 form: %{
                   customer_name: "Mrs Holm",
                   customer_phone_number: "040 123 4567",
                   fulfillment_option_id: ctx.pickup.id,
                   fulfillment_date: Date.to_iso8601(tomorrow()),
                   gift: "true",
                   recipient_name: "St. Olof's church",
                   card_message: "Rest in peace",
                   line_items: %{
                     "0" => %{"product_name" => "Wreath", "unit_price" => "85", "tax_rate_id" => ctx.tax_rate.id}
                   }
                 }
               )
               |> render_submit()

      order = Orders.get_order_for_admin!(id, actor: ctx.admin)
      assert order.gift
      assert order.recipient_name == "St. Olof's church"
      assert order.card_message == "Rest in peace"
    end

    test "warns about a closed day without refusing it", ctx do
      shop_calendar(available_days: [])

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/new")

      view
      |> form("#order-form",
        form: %{fulfillment_option_id: ctx.pickup.id, fulfillment_date: Date.to_iso8601(tomorrow())}
      )
      |> render_change()

      assert has_element?(view, "#date-warning", "normally closed")
    end

    test "prices the delivery as soon as the address is entered", ctx do
      delivery = delivery_option(ctx)
      stub_geocoding(8_000)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/new")

      view |> form("#order-form", form: %{fulfillment_option_id: delivery.id}) |> render_change()
      view |> form("#order-form", form: %{delivery_address: "Kyrkvägen 5"}) |> render_change()

      view |> element("#form_delivery_address") |> render_blur(%{"value" => "Kyrkvägen 5"})

      assert render_async(view, 500) =~ "8.0 km"
      assert has_element?(view, "#delivery-quote", "13.00")
      assert has_element?(view, "#delivery-quote", "Delivering to Kyrkvägen 5, Vasa")
    end

    test "says when Jennie's own fee replaces the quoted one", ctx do
      delivery = delivery_option(ctx)
      stub_geocoding(8_000)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/new")

      view |> form("#order-form", form: %{fulfillment_option_id: delivery.id}) |> render_change()
      view |> form("#order-form", form: %{delivery_address: "Kyrkvägen 5"}) |> render_change()
      view |> element("#form_delivery_address") |> render_blur(%{"value" => "Kyrkvägen 5"})
      render_async(view, 500)

      view |> form("#order-form", form: %{fulfillment_fee_override: "5"}) |> render_change()

      assert has_element?(view, "#delivery-quote", "your own fee replaces this")
    end

    test "says when an address can't be delivered to", ctx do
      delivery = delivery_option(ctx)
      stub_geocoding(50_000)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/new")

      view |> form("#order-form", form: %{fulfillment_option_id: delivery.id}) |> render_change()
      view |> form("#order-form", form: %{delivery_address: "Far away 1"}) |> render_change()

      view |> element("#form_delivery_address") |> render_blur(%{"value" => "Far away 1"})
      render_async(view, 500)

      assert has_element?(view, "#delivery-quote", "Outside delivery range")
      assert has_element?(view, "#delivery-quote", "You can still set your own fee")
    end

    test "shows a line's problem inside that line, after saving", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/new")
      render_click(view, "add_line", %{"kind" => "custom"})

      view
      |> form("#order-form",
        form: %{
          customer_name: "Mrs Holm",
          line_items: %{"0" => %{"product_name" => "Spray", "unit_price" => "lots", "quantity" => "1"}}
        }
      )
      |> render_submit()

      assert has_element?(view, "#form_line_items_0_unit_price-error", "enter a price")
      assert has_element?(view, ~s|input[name="form[line_items][0][unit_price]"][aria-invalid="true"]|)
      assert has_element?(view, ~s|button[aria-label="Remove item 1"]|)
    end

    test "keeps quiet about missing items until Jennie tries to save", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/new")

      html = view |> form("#order-form", form: %{customer_name: "Mrs Holm"}) |> render_change()

      refute html =~ "Add at least one item"
    end

    test "shows what is missing instead of saving", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/new")

      html =
        view
        |> form("#order-form", form: %{customer_name: "Mrs Holm"})
        |> render_submit()

      assert html =~ "Add at least one item"
      assert html =~ "enter a phone number or an email"
    end
  end

  describe "editing" do
    test "an unpaid custom order opens in the full form", ctx do
      order = place_custom_order(ctx)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/#{order.id}/edit")

      assert has_element?(view, "[data-testid=order-line]")

      assert {:error, {:live_redirect, _}} =
               view
               |> form("#order-form",
                 form: %{
                   line_items: %{
                     "0" => %{
                       "product_name" => "Funeral spray, larger",
                       "unit_price" => "120.00",
                       "tax_rate_id" => ctx.tax_rate.id,
                       "quantity" => "1"
                     }
                   }
                 }
               )
               |> render_submit()

      assert Decimal.equal?(Orders.get_order_for_admin!(order.id, actor: ctx.admin).grand_total, "120.00")
    end

    test "a paid order can change too, and its page shows what is left to collect", ctx do
      order = place_custom_order(ctx)
      {:ok, order} = Orders.record_payment(order, "85.00", :zettle, actor: ctx.admin)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/#{order.id}/edit")

      assert {:error, {:live_redirect, _}} =
               view
               |> form("#order-form",
                 form: %{
                   line_items: %{
                     "0" => %{
                       "product_name" => "Funeral spray",
                       "unit_price" => "95.00",
                       "tax_rate_id" => ctx.tax_rate.id,
                       "quantity" => "1"
                     }
                   }
                 }
               )
               |> render_submit()

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/#{order.id}")

      assert has_element?(view, "#order-balance", "To collect €10.00")
      assert has_element?(view, ~s|#order-balance-form input[value="10.00"]|)
    end

    test "a catalogue line keeps the price it was sold at, while its quantity changes", ctx do
      order =
        place_custom_order(ctx, %{
          line_items: [%{"kind" => "catalogue", "product_variant_id" => ctx.variant.id, "quantity" => "1"}]
        })

      Ash.Seed.update!(ctx.variant, %{price: Decimal.new("59.00")})
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/#{order.id}/edit")

      assert {:error, {:live_redirect, _}} =
               view
               |> form("#order-form", form: %{line_items: %{"0" => %{"quantity" => "2"}}})
               |> render_submit()

      [line] = Ash.load!(order, :line_items, authorize?: false, reuse_values?: false).line_items
      assert {line.quantity, Decimal.to_string(line.unit_price)} == {2, "49.00"}
    end

    test "keeps a retired VAT rate when editing another field", ctx do
      order = place_custom_order(ctx)
      generate(tax_rate(name: "Current rate", percentage: "0.14"))
      {:ok, _rate} = Edenflowers.Pricing.retire_tax_rate(ctx.tax_rate, actor: ctx.admin)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/#{order.id}/edit")

      assert {:error, {:live_redirect, _}} =
               view
               |> form("#order-form", form: %{customer_name: "Mrs Holm-Smith"})
               |> render_submit()

      [line] = Ash.load!(order, :line_items, authorize?: false, reuse_values?: false).line_items
      assert Decimal.equal?(line.tax_rate, ctx.tax_rate.percentage)
    end
  end

  describe "the order page" do
    test "shows the payment link to copy while the order is unpaid", ctx do
      order = place_custom_order(ctx)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/#{order.id}")

      assert has_element?(view, ~s|#payment-link-url[value$="/pay/#{order.payment_link_token}"]|)
      assert has_element?(view, "header", "Unpaid")
    end

    test "offers to text or WhatsApp the payment link in the customer's language", ctx do
      order = place_custom_order(ctx)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/#{order.id}")

      body =
        URI.encode(
          "Hi Mrs, you can pay €85.00 for your Eden Flowers order #{order.order_reference} here: " <>
            EdenflowersWeb.PaymentLink.url_for(order),
          &URI.char_unreserved?/1
        )

      assert has_element?(view, ~s|#order-payment-link a[href="sms:+358401234567?&body=#{body}"]|)
      assert has_element?(view, ~s|#order-payment-link a[href="https://wa.me/358401234567?text=#{body}"]|)
    end

    test "emails the payment link to the customer", ctx do
      order = place_custom_order(ctx, %{customer_email: "son@example.com", payment_terms: :invoice})

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/#{order.id}")

      assert has_element?(view, "#order-balance", "To collect €85.00")
      render_click(view, "email_payment_link")

      order = Ash.reload!(order, authorize?: false)

      assert_email_sent(fn email ->
        assert email.to == [{"", "son@example.com"}]
        assert email.text_body =~ "/pay/#{order.payment_link_token}"
      end)

      assert has_element?(view, ~s|#payment-link-url[value$="/pay/#{order.payment_link_token}"]|)
    end

    test "records a payment", ctx do
      order = place_custom_order(ctx)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/#{order.id}")

      view
      |> form("#order-balance-form", payment: %{payment_method: "mobilepay", amount: "85,00"})
      |> render_submit()

      assert has_element?(view, "#order-payments", "MobilePay")
      refute has_element?(view, "#payment-link-url")
      refute has_element?(view, "#order-balance-form")
    end

    test "records a paid Zervant invoice", ctx do
      order = place_custom_order(ctx)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/#{order.id}")

      view
      |> form("#order-balance-form", payment: %{payment_method: "zervant", amount: "85,00"})
      |> render_submit()

      assert has_element?(view, "#order-payments", "Invoice (Zervant)")
    end

    test "logs what happened to the order", ctx do
      order = place_custom_order(ctx)
      {:ok, _order} = Orders.record_payment(order, "85.00", :mobilepay, actor: ctx.admin)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/#{order.id}")

      assert has_element?(view, "#order-log", "Placed by Jennie")
      assert has_element?(view, "#order-log", "1 × Funeral spray")
      assert has_element?(view, "#order-payments", "MobilePay")
    end

    test "saves the florist note", ctx do
      order = place_custom_order(ctx)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/#{order.id}")

      view
      |> form("#florist-note-form", note: %{florist_note: "Service at 11:00, deliver by 10:30"})
      |> render_submit()

      assert Orders.get_order_for_admin!(order.id, actor: ctx.admin).florist_note ==
               "Service at 11:00, deliver by 10:30"
    end

    test "cancels the order and closes its payment link", ctx do
      order = place_custom_order(ctx) |> Ash.Seed.update!(%{payment_intent_id: "pi_link"})
      expect(StripeAPI.Mock, :cancel_payment_intent, fn %{id: "pi_link"} -> {:ok, %{id: "pi_link"}} end)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/#{order.id}")

      render_click(view, "cancel_order")

      assert has_element?(view, "header", "Cancelled")
      refute has_element?(view, "header", "Unpaid")
      refute has_element?(view, "#payment-link-url")
      refute has_element?(view, ~s|button[phx-click="confirm_fulfillment"]|)
    end

    test "asks before fulfilling an unpaid order", ctx do
      order = place_custom_order(ctx)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/orders/#{order.id}")

      view |> element(~s|button[phx-click="confirm_fulfillment"]|) |> render_click()

      assert has_element?(view, "#confirm-fulfillment", "This order is still unpaid.")
      assert Orders.get_order_for_admin!(order.id, actor: ctx.admin).fulfillment_status == :pending
    end
  end
end
