defmodule EdenflowersWeb.CheckoutComponents do
  use EdenflowersWeb, :html

  @checkout_states [:contact_details, :gift_options, :delivery, :payment]

  attr :state, :atom, required: true
  attr :order, :map, required: true
  slot :inner_block

  def steps(assigns) do
    assigns = assign(assigns, :states, @checkout_states)

    ~H"""
    <ol class="flex flex-col">
      <.checkout_step
        :for={state <- @states}
        state={state}
        current_state={@state}
        order={@order}
      >
        <%= if state == @state do %>
          {render_slot(@inner_block)}
        <% end %>
      </.checkout_step>
    </ol>
    """
  end

  attr :state, :atom, required: true
  attr :current_state, :atom, required: true
  attr :order, :map, required: true
  slot :inner_block

  defp checkout_step(assigns) do
    position_for = state_index(assigns.current_state)
    position = state_index(assigns.state)

    relative =
      cond do
        position < position_for -> :past
        position == position_for -> :current
        true -> :future
      end

    assigns =
      assigns
      |> assign(:relative, relative)
      |> assign(:position, position + 1)
      |> assign(:title, step_title(assigns.state))
      |> assign(:summary, if(relative == :past, do: step_summary(assigns.state, assigns.order)))

    ~H"""
    <li class={["border-base-content/12 py-8 md:py-10", @position > 1 && "border-t"]}>
      <div class="flex items-baseline justify-between gap-4">
        <div class="flex items-baseline gap-3">
          <span
            aria-hidden="true"
            class={["eyebrow tabular-nums", @relative == :current && "text-[var(--color-link-underline)]", @relative != :current && "text-base-content/55"]}
          >
            {String.pad_leading(Integer.to_string(@position), 2, "0")}
          </span>
          <h2 class={["section-title flex items-baseline gap-2", @relative == :past && "text-base-content/70", @relative == :future && "text-base-content/40"]}>
            <span class="sr-only">{step_label(@relative)}: </span>
            <span>{@title}</span>
            <.icon
              :if={@relative == :past}
              name="hero-check-mini"
              class="size-4 text-base-content/70 self-center"
            />
          </h2>
        </div>
        <.link
          :if={@relative == :past}
          phx-click={JS.push("edit_step", value: %{state: @state})}
          class="link-underline-hover-nav shrink-0 text-sm"
        >
          {~t"Edit"}
        </.link>
      </div>

      <p :if={@relative == :past && @summary} class="text-base-content/70 mt-3">
        {@summary}
      </p>

      <div :if={@relative == :current} class="mt-8">
        {render_slot(@inner_block)}
      </div>
    </li>
    """
  end

  defp state_index(state), do: Enum.find_index(@checkout_states, &(&1 == state))

  defp step_title(:contact_details), do: ~t"Your details"
  defp step_title(:gift_options), do: ~t"Gift options"
  defp step_title(:delivery), do: ~t"Delivery"
  defp step_title(:payment), do: ~t"Payment"

  defp step_label(:past), do: ~t"Completed"
  defp step_label(:current), do: ~t"Current step"
  defp step_label(:future), do: ~t"Upcoming"

  defp step_summary(:contact_details, %{customer_name: name, customer_email: email})
       when is_binary(name) and is_binary(email),
       do: "#{name} · #{email}"

  defp step_summary(:gift_options, %{gift: false}), do: ~t"For me"
  defp step_summary(:gift_options, %{gift: true, recipient_name: name}) when is_binary(name), do: ~t"For #{name}"
  defp step_summary(:gift_options, _), do: nil

  defp step_summary(:delivery, %{fulfillment_method: method, fulfillment_date: date} = order)
       when not is_nil(method) and not is_nil(date) do
    method_label = if method == :delivery, do: ~t"Delivery", else: ~t"Pickup"
    address = if method == :delivery, do: order.delivery_address, else: nil

    [method_label, format_date(date), address]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp step_summary(_, _), do: nil

  defp format_date(%Date{} = date) do
    locale = Localize.get_locale().cldr_locale_id
    Localize.Date.to_string!(date, locale: locale, format: :medium)
  end

  defp format_date(_), do: nil
end
