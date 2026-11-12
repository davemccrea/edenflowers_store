defmodule EdenflowersWeb.Admin.TimelineTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias EdenflowersWeb.Admin.Components
  alias EdenflowersWeb.Admin.OrderLog
  alias EdenflowersWeb.Admin.SubscriptionLog

  test "failure indicators follow recorded actions, including in a single markerless history" do
    for {action, warning?} <- [
          record_fulfillment_email_failure: true,
          record_receipt_email_failure: true,
          record_payment_received_email_failure: true,
          record_order_details_email_failure: true,
          record_order_updated_email_failure: true,
          record_payment_failed_email_failure: true,
          place_unpaid_occurrence: true,
          send_payment_failed_email: false,
          cancel: false
        ] do
      version = %{
        id: "event",
        version_action_name: action,
        version_action_type: :update,
        version_inserted_at: ~U[2020-11-01 12:00:00Z],
        changes: %{},
        items: nil
      }

      entries = OrderLog.entries([version], [], "en-GB")

      document =
        render_component(&Components.history_timeline/1, id: "history", entries: entries, locale: "en-GB")
        |> LazyHTML.from_fragment()

      has_warning? = document |> LazyHTML.query(".hero-exclamation-triangle") |> LazyHTML.to_tree() != []
      assert has_warning? == warning?
    end
  end

  test "titles name the email or step for the kind of order" do
    for {action, metadata, order, title} <- [
          {:send_receipt_email, %{}, %{gift_voucher_sale?: true}, "Gift voucher emailed"},
          {:send_payment_received_email, %{}, %{gift_voucher_sale?: true}, "Gift voucher emailed"},
          {:record_payment_received_email_failure, %{}, %{gift_voucher_sale?: true}, "Gift voucher email failed"},
          {:send_payment_received_email, %{}, %{}, "Payment received emailed"},
          {:send_receipt_email, %{}, %{origin: :subscription}, "Charge confirmation emailed"},
          {:record_receipt_email_failure, %{}, %{origin: :subscription}, "Charge confirmation failed"},
          {:send_receipt_email, %{}, %{origin: :online}, "Receipt emailed"},
          {:email_receipt, %{}, %{}, "Receipt emailed"},
          {:mark_fulfilled, %{}, %{fulfillment_method: :delivery}, "Delivered"},
          {:mark_fulfilled, %{}, %{fulfillment_method: :pickup}, "Collected"},
          {:send_fulfillment_email, %{fulfillment_email: "left_at_door"}, %{},
           "Left at the door email sent, with photo"},
          {:send_fulfillment_email, %{fulfillment_email: "delivered"}, %{}, "Delivered email sent"},
          {:send_fulfillment_email, %{}, %{}, "Fulfillment confirmation emailed"},
          {:place_paid_by_voucher, %{}, %{}, "Placed online"}
        ] do
      version =
        Map.merge(
          %{
            id: "event",
            version_action_name: action,
            version_action_type: :update,
            version_inserted_at: ~U[2020-11-01 12:00:00Z],
            changes: %{},
            items: nil
          },
          metadata
        )

      assert [%{title: ^title}] = OrderLog.entries([version], [], "en-GB", order)
    end
  end

  test "only a refused subscription occurrence survives filtering and carries a warning" do
    versions =
      for state <- ["active", "payment_failed"] do
        %{
          id: state,
          version_action_name: :create_occurrence,
          version_action_type: :update,
          version_inserted_at: ~U[2020-11-01 12:00:00Z],
          changes: %{"state" => state}
        }
      end

    assert [%{id: "version-payment_failed", warning?: true}] = SubscriptionLog.entries(versions, %{}, "en-GB")
  end

  test "a single event has no marker or gutter, but one event on each of two days keeps its markers" do
    entries =
      [{"newer", ~U[2020-11-01 12:00:00Z]}, {"older", ~U[2020-10-31 12:00:00Z]}]
      |> Enum.map(fn {id, at} -> %{id: id, at: at, title: id, details: []} end)

    for {size, expected_markers} <- [{1, 0}, {2, 2}] do
      document =
        render_component(&Components.history_timeline/1,
          id: "history",
          entries: Enum.take(entries, size),
          locale: "en-GB"
        )
        |> LazyHTML.from_fragment()

      # Count markers across the complete event history, not separately for each date group.
      # Date headers must not add event markers of their own.
      assert length(document |> LazyHTML.query(".rounded-full") |> LazyHTML.to_tree()) == expected_markers

      if size == 1 do
        assert document |> LazyHTML.query(".pl-7") |> LazyHTML.to_tree() == []
      end
    end
  end

  test "an edit's title names up to two changed fields and counts the rest" do
    assert OrderLog.edited_title([]) == "Edited"
    assert OrderLog.edited_title([{"Date", "1.11.2020"}]) == "Edited · Date"

    assert OrderLog.edited_title([{"Date", "x"}, {"Recipient", "x"}, {"Email", "x"}, {"Items", ["x"]}]) ==
             "Edited · Date, Recipient +2"
  end

  test "day headings say Today and Yesterday, then the weekday and date" do
    today = Edenflowers.ShopTime.today()

    entries =
      for days_ago <- 0..2 do
        at = DateTime.new!(Date.add(today, -days_ago), ~T[12:00:00], Edenflowers.ShopTime.timezone())
        %{id: "#{days_ago}", at: at, title: "event", details: []}
      end

    headings =
      render_component(&Components.history_timeline/1, id: "history", entries: entries, locale: "en-GB")
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("h3")
      |> Enum.map(&(LazyHTML.text(&1) |> String.trim()))

    assert ["Today", "Yesterday", weekday_and_date] = headings
    assert weekday_and_date =~ ~r/^\w{3} \d/
  end

  test "groups history by Helsinki day and shows each date once with local event times" do
    entries =
      [
        {"late", ~U[2020-10-31 22:30:00Z]},
        {"midnight", ~U[2020-10-31 22:00:00Z]},
        {"earlier", ~U[2020-10-31 21:30:00Z]}
      ]
      |> Enum.map(fn {id, at} -> %{id: id, at: at, title: id, details: []} end)

    html = render_component(&Components.history_timeline/1, id: "history", entries: entries, locale: "en-GB")
    document = LazyHTML.from_fragment(html)

    headings = document |> LazyHTML.query("h3") |> LazyHTML.to_tree()
    assert length(headings) == 2
    assert length(document |> LazyHTML.query("#history > li[id^=history-entry-]") |> LazyHTML.to_tree()) == 3
    assert document |> LazyHTML.query("#history-date-2020-11-01") |> LazyHTML.text() |> String.trim() == "Sun 1.11.2020"

    assert document |> LazyHTML.query("#history-date-2020-10-31") |> LazyHTML.text() |> String.trim() ==
             "Sat 31.10.2020"

    assert document |> LazyHTML.query("time") |> Enum.map(&(LazyHTML.text(&1) |> String.trim())) == [
             "00:30",
             "00:00",
             "23:30"
           ]

    assert document |> LazyHTML.query("time") |> LazyHTML.attribute("datetime") ==
             Enum.map(entries, &DateTime.to_iso8601(&1.at))

    assert length(document |> LazyHTML.query("time") |> LazyHTML.attribute("title")) == 3
  end
end
