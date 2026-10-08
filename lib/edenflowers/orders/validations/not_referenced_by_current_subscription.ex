defmodule Edenflowers.Orders.Validations.NotReferencedByCurrentSubscription do
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Orders.Subscription

  @impl true
  def validate(changeset, opts, context) do
    if applies?(changeset, opts[:changing_to]) and referenced?(changeset, opts[:reference], context) do
      {:error, field: opts[:field], message: ~t"is used by a current subscription"}
    else
      :ok
    end
  end

  defp applies?(_changeset, nil), do: true

  defp applies?(changeset, {field, value}) do
    Ash.Changeset.changing_attribute?(changeset, field) and Ash.Changeset.get_attribute(changeset, field) == value
  end

  defp referenced?(changeset, reference, context) do
    query =
      case reference do
        :product -> Ash.Query.filter(Subscription, product_variant.product_id == ^changeset.data.id)
        :product_variant -> Ash.Query.filter(Subscription, product_variant_id == ^changeset.data.id)
        :fulfillment_option -> Ash.Query.filter(Subscription, fulfillment_option_id == ^changeset.data.id)
      end

    query
    |> Ash.Query.filter(state != :cancelled)
    |> Ash.exists?(Ash.Context.to_opts(context, authorize?: false))
  end
end
