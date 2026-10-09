defmodule EdenflowersWeb.Admin.SubscriptionLog do
  @moduledoc """
  Turns a subscription's paper trail versions into the log on its admin page,
  newest first.

  Each Occurrence the job creates is an order, already listed on the page, so
  the job's versions show only when it holds the subscription for a refused
  card. A version names its user when a person made the change; the job's and
  webhook's changes are made by the system and name no one.
  """
  use GettextSigils, backend: EdenflowersWeb.Gettext

  import EdenflowersWeb.Admin.Components, only: [variant_size_label: 1]

  alias Edenflowers.Format
  alias EdenflowersWeb.Checkout.Fields

  @doc "`sizes` maps each of the product's variant ids to its size, since a version holds only the id."
  def entries(versions, sizes, locale) do
    versions
    |> Enum.reject(&routine_occurrence?/1)
    |> Enum.map(&entry(&1, sizes, locale))
    |> Enum.sort_by(& &1.at, {:desc, DateTime})
  end

  defp routine_occurrence?(%{version_action_name: :create_occurrence, changes: changes}),
    do: changes["state"] != "payment_failed"

  defp routine_occurrence?(_version), do: false

  defp entry(version, sizes, locale) do
    %{
      at: version.version_inserted_at,
      title: title(version),
      details: details(version, sizes, locale)
    }
  end

  defp title(%{user: %{name: name}} = version) when is_binary(name),
    do: ~t"#{event = event(version)} · #{name = name}"

  defp title(%{user: %{email: email}} = version) when not is_nil(email),
    do: ~t"#{event = event(version)} · #{name = to_string(email)}"

  defp title(version), do: event(version)

  defp event(%{version_action_name: action}) do
    case action do
      :activate -> ~t"Started"
      :send_setup_email -> ~t"Confirmation emailed"
      :create_occurrence -> ~t"Card refused, held until the payment link is paid"
      :reactivate -> ~t"Payment received, deliveries restarted"
      :pause -> ~t"Paused"
      :resume -> ~t"Resumed"
      :change -> ~t"Changed"
      :replace_card -> ~t"Card replaced"
      :cancel -> ~t"Cancelled"
      other -> to_string(other)
    end
  end

  # A creation's fields are the whole subscription, already on the page.
  defp details(%{version_action_type: :create}, _sizes, _locale), do: []

  defp details(%{version_action_name: :replace_card, changes: changes}, _sizes, _locale) do
    card =
      Fields.card_label(%{
        card_brand: changes["card_brand"],
        card_last4: changes["card_last4"],
        card_exp_month: changes["card_exp_month"],
        card_exp_year: changes["card_exp_year"]
      })

    if card, do: [{~t"Card", card}], else: []
  end

  defp details(%{changes: changes}, sizes, locale) do
    Enum.flat_map(
      [
        {"product_variant_id", ~t"Size", &size(&1, sizes)},
        {"interval_weeks", ~t"Interval", &Fields.interval_label/1},
        {"next_fulfillment_date", ~t"Next delivery", &Format.date(Date.from_iso8601!(&1), locale)}
      ],
      fn {field, label, show} ->
        if Map.has_key?(changes, field), do: [{label, show.(changes[field])}], else: []
      end
    )
  end

  defp size(variant_id, sizes) do
    case Map.fetch(sizes, variant_id) do
      {:ok, size} -> variant_size_label(size)
      :error -> "—"
    end
  end
end
