defmodule EdenflowersWeb.Store.GiftVoucherLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders.Order
  alias EdenflowersWeb.Store.GiftVoucherLive

  setup :verify_on_exit!

  @details %{
    "amount" => "70",
    "recipient_name" => "Mia",
    "card_message" => "Grattis!",
    "voucher_locale" => "fi",
    "customer_name" => "Anna Buyer",
    "customer_email" => "anna@example.com"
  }

  defp sale(id), do: Ash.get!(Order, id, load: [:grand_total], authorize?: false)

  test "shows a voucher skeleton until the first preview is ready", %{conn: conn} do
    html = conn |> get("/en/gift-voucher") |> html_response(200)
    assert html =~ ~s(data-testid="voucher-preview-skeleton")
    assert html =~ "Loading preview…"

    {:ok, view, _html} = live(conn, "/en/gift-voucher")
    render_async(view, 5_000)

    assert has_element?(view, "#voucher-preview[aria-busy=false] img[data-testid=voucher-preview]")
    refute has_element?(view, "[data-testid=voucher-preview-skeleton]")
  end

  for path <- ["/sv/presentkort", "/fi/lahjakortti", "/en/gift-voucher"] do
    @path path
    test "browser Back from payment restores the voucher form at #{path}", %{conn: conn} do
      path = @path
      {:ok, view, _html} = live(conn, path)
      details = Map.put(@details, "voucher_style", "cream")
      seed = snow_seed(view)

      view |> form("#gift-voucher-form", form: details) |> render_submit()
      assert_patch(view, path <> "?step=payment")
      assert has_element?(view, "[data-testid=payment-section]")
      [%{id: id}] = Ash.read!(Order, authorize?: false)

      render_patch(view, path)
      refute has_element?(view, "[data-testid=payment-section]")

      for field <- ~w(recipient_name customer_name customer_email) do
        assert has_element?(view, "#gift-voucher-form input[name='form[#{field}]'][value='#{details[field]}']")
      end

      for field <- ~w(amount voucher_locale) do
        assert has_element?(view, "select[name='form[#{field}]'] option[selected][value='#{details[field]}']")
      end

      assert has_element?(view, "textarea[name='form[card_message]']", details["card_message"])
      assert has_element?(view, "input[name='form[voucher_style]'][value=cream][checked]")
      assert snow_seed(view) == seed

      render_patch(view, path <> "?step=payment")
      assert has_element?(view, "[data-testid=payment-section]")
      render_patch(view, path)
      assert has_element?(view, "#gift-voucher-form")

      revised = %{details | "amount" => "40", "recipient_name" => "Ella"}
      view |> form("#gift-voucher-form", form: revised) |> render_submit()
      assert_patch(view, path <> "?step=payment")
      assert has_element?(view, "[data-testid=payment-section]", "Ella")
      assert [%{id: ^id}] = Ash.read!(Order, authorize?: false)
      assert Decimal.eq?(sale(id).grand_total, 40)

      expect(StripeAPI.Mock, :create_payment_intent, fn 4000, %{"order_id" => ^id}, nil ->
        {:ok, %{id: "pi_voucher_back", client_secret: "pi_back_secret", amount: 4000}}
      end)

      view |> element("#gift-voucher-payment-form") |> render_submit()
      assert_push_event(view, "stripe:process_payment", %{client_secret: "pi_back_secret"})
    end
  end

  test "a reload resumes the voucher at payment and on the form", %{conn: conn} do
    conn = get(conn, "/en/gift-voucher")
    {:ok, view, _html} = live(conn)
    view |> form("#gift-voucher-form", form: @details) |> render_submit()
    assert_patch(view, "/en/gift-voucher?step=payment")

    {:ok, view, _html} = live(conn, "/en/gift-voucher?step=payment")
    assert has_element?(view, "[data-testid=payment-section]", "Mia")

    {:ok, view, _html} = live(conn, "/en/gift-voucher")
    assert has_element?(view, "#gift-voucher-form input[name='form[recipient_name]'][value=Mia]")

    view |> form("#gift-voucher-form", form: %{@details | "recipient_name" => "Ella"}) |> render_submit()
    assert has_element?(view, "[data-testid=payment-section]", "Ella")
    assert [%{recipient_name: "Ella"}] = Ash.read!(Order, authorize?: false)
  end

  test "a cancelled MobilePay payment returns to the voucher's payment step", %{conn: conn} do
    conn = get(conn, "/en/gift-voucher")
    {:ok, view, _html} = live(conn)
    view |> form("#gift-voucher-form", form: @details) |> render_submit()
    [%{id: id}] = Ash.read!(Order, authorize?: false)

    conn = get(conn, "/checkout/complete/#{id}?redirect_status=failed")

    {:ok, view, _html} = live(conn, redirected_to(conn))
    assert has_element?(view, "[data-testid=payment-section]", "Mia")
    assert render(view) =~ "didn&#39;t go through"
  end

  test "a payment URL without a voucher returns to the form", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/en/gift-voucher"}}} = live(conn, "/en/gift-voucher?step=payment")
    {:ok, view, _html} = live(conn, "/en/gift-voucher")

    assert has_element?(view, "#gift-voucher-form")
    refute has_element?(view, "[data-testid=payment-section]")
    assert Ash.read!(Order, authorize?: false) == []
  end

  test "a guest buys a voucher in Swedish, changes the amount, then pays by card", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/sv/presentkort")

    view |> form("#gift-voucher-form", form: @details) |> render_submit()
    assert has_element?(view, "[data-testid=payment-section]", "till Mia")

    [%{id: id}] = Ash.read!(Order, authorize?: false)
    started = sale(id)
    assert started.state == :payment
    assert Decimal.eq?(started.grand_total, 70)
    assert started.voucher_locale == "fi"
    assert started.locale == "sv-FI"

    view |> element("button", "Ändra") |> render_click()
    view |> form("#gift-voucher-form", form: %{@details | "amount" => "40"}) |> render_submit()
    assert Decimal.eq?(sale(id).grand_total, 40)

    expect(StripeAPI.Mock, :create_payment_intent, fn 4000, %{"order_id" => ^id}, nil ->
      {:ok, %{id: "pi_voucher", client_secret: "pi_secret", amount: 4000}}
    end)

    view |> element("#gift-voucher-payment-form") |> render_submit()
    assert_push_event(view, "stripe:process_payment", %{client_secret: "pi_secret"})
  end

  test "previews the voucher as it's filled in, and offers Christmas, with its snow shuffled, only while Jennie does",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/en/gift-voucher")
    # Typst takes longer than render_async's default 100 ms under a full test run.
    render_async(view, 5_000)
    assert has_element?(view, "img[data-testid=voucher-preview]")
    refute has_element?(view, "input[name='form[voucher_style]'][value=christmas]")

    calendar = Edenflowers.Fulfillment.get_shop_calendar!(authorize?: false)
    Edenflowers.Fulfillment.set_christmas_vouchers_online!(calendar, true, authorize?: false)

    {:ok, view, _html} = live(conn, "/en/gift-voucher")
    view |> form("#gift-voucher-form", form: %{"voucher_style" => "christmas"}) |> render_change()
    seed = snow_seed(view)
    view |> element("[data-testid=shuffle-snow]") |> render_click()
    assert snow_seed(view) != seed

    shuffled = snow_seed(view)
    view |> form("#gift-voucher-form", form: Map.put(@details, "voucher_style", "christmas")) |> render_submit()

    [%{id: id}] = Ash.read!(Order, authorize?: false)
    assert %{voucher_style: :christmas, voucher_snow_seed: ^shuffled} = sale(id)
  end

  # The PDF is printed with the snow the buyer last saw in the preview.
  defp snow_seed(view) do
    html = view |> element("input[name='form[voucher_snow_seed]']") |> render()
    [_, seed] = Regex.run(~r/value="(\d+)"/, html)
    String.to_integer(seed)
  end

  test "asks who the voucher is for before taking payment", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/en/gift-voucher")

    view |> form("#gift-voucher-form", form: %{@details | "recipient_name" => ""}) |> render_submit()

    refute has_element?(view, "[data-testid=payment-section]")
    assert has_element?(view, "#gift-voucher-form", "This field is required")
    assert_push_event(view, "focus-first-error", %{})
    assert Ash.read!(Order, authorize?: false) == []
  end

  test "explains when the chosen style stops being offered while the form is open", %{conn: conn} do
    calendar = Edenflowers.Fulfillment.get_shop_calendar!(authorize?: false)
    Edenflowers.Fulfillment.set_christmas_vouchers_online!(calendar, true, authorize?: false)
    {:ok, view, _html} = live(conn, "/en/gift-voucher")

    Edenflowers.Fulfillment.set_christmas_vouchers_online!(calendar, false, authorize?: false)
    view |> form("#gift-voucher-form", form: Map.put(@details, "voucher_style", "christmas")) |> render_submit()

    assert has_element?(view, "#form_voucher_style-error", "The Christmas voucher isn't available right now.")
    assert has_element?(view, "input[value=christmas][aria-invalid=true][aria-describedby=form_voucher_style-error]")
    assert_push_event(view, "focus-first-error", %{})
    refute has_element?(view, "[data-testid=payment-section]")
  end

  test "a failed preview is marked unavailable and the same voucher can be retried" do
    voucher = %{
      amount: Decimal.new(50),
      locale: "en-GB",
      style: :cream,
      snow_seed: 123,
      recipient_name: "Mia",
      message: "Grattis!"
    }

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        sale: %{
          grand_total: voucher.amount,
          voucher_locale: voucher.locale,
          voucher_style: voucher.style,
          voucher_snow_seed: voucher.snow_seed,
          recipient_name: voucher.recipient_name,
          card_message: voucher.message
        },
        editing?: false,
        preview: "old-image",
        previewed: voucher,
        preview_loading?: true,
        preview_error?: false
      }
    }

    ExUnit.CaptureLog.capture_log(fn ->
      {:noreply, failed} = GiftVoucherLive.handle_async(:preview, {:ok, {:error, :unavailable}}, socket)
      assert failed.assigns.preview_error?
      refute failed.assigns.preview_loading?
      assert is_nil(failed.assigns.previewed)

      {:noreply, retrying} = GiftVoucherLive.handle_event("retry_preview", %{}, failed)
      assert retrying.assigns.preview_loading?
      refute retrying.assigns.preview_error?
      assert retrying.assigns.previewed == voucher

      {:noreply, loaded} = GiftVoucherLive.handle_async(:preview, {:ok, {:ok, "new-image"}}, retrying)
      assert loaded.assigns.preview == Base.encode64("new-image")
      refute loaded.assigns.preview_loading?
      refute loaded.assigns.preview_error?
    end)
  end
end
