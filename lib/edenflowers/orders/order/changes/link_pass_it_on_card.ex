defmodule Edenflowers.Orders.Order.Changes.LinkPassItOnCard do
  @moduledoc """
  Links the pass-it-on card with the `code` argument to this gift order, or with `remove?: true` unlinks the one it
  has, through `Promotion.link_gift_order`. The card's code goes in the order log's version for the action, since
  the link lives on the card, not the order row.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "admin"]

  alias Edenflowers.Pricing

  @impl true
  def change(changeset, opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      if opts[:remove?], do: remove(changeset, context), else: link(changeset, context)
    end)
  end

  defp link(changeset, context) do
    code = changeset |> Ash.Changeset.get_argument(:code) |> to_string()

    case Pricing.get_pass_it_on_card(code, authorize?: false) do
      {:ok, nil} ->
        Ash.Changeset.add_error(changeset, field: :code, message: ~t"No pass-it-on card has the code #{code}.")

      {:ok, card} ->
        case Pricing.link_card_to_gift_order(card, changeset.data.id, actor: context.actor) do
          {:ok, card} ->
            log_card(changeset, card)

          {:error, _opened_or_taken} ->
            message = ~t"Card #{code} has already been opened, or went with another order."
            Ash.Changeset.add_error(changeset, field: :code, message: message)
        end
    end
  end

  defp remove(changeset, context) do
    order = Ash.load!(changeset.data, :pass_it_on_card, authorize?: false, reuse_values?: false)

    log_card(changeset, Pricing.link_card_to_gift_order!(order.pass_it_on_card, nil, actor: context.actor))
  end

  defp log_card(changeset, card),
    do: Ash.Changeset.set_context(changeset, %{paper_trail_metadata: %{pass_it_on_card: to_string(card.code)}})
end
