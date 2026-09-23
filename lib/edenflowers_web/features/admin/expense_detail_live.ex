defmodule EdenflowersWeb.Admin.ExpenseDetailLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Layouts
  alias Edenflowers.Expenses
  alias Edenflowers.Expenses.Expense
  alias Edenflowers.Format

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Ash.get(Expense, id, actor: socket.assigns.current_user) do
      {:ok, expense} ->
        {:ok,
         socket
         |> assign(:page_title, ~t"Expense: #{expense.vendor_name || id}")
         |> assign(:locale, Localize.get_locale())
         |> assign(:expense, expense)
         |> assign(:form, build_form(expense, socket.assigns.current_user))}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, ~t"Expense not found.")
         |> push_navigate(to: ~p"/admin/expenses")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page width="narrow">
        <.admin_page_header
          title={@expense.vendor_name || ~t"Unknown vendor"}
          back={~p"/admin/expenses"}
          back_label={~t"Expenses"}
        >
          <:actions :if={@expense.reviewed_at}>
            <span class="badge badge-sm badge-success admin-badge-success gap-1">
              <.icon name="hero-check" class="h-3 w-3" /> {~t"Reviewed"}
            </span>
          </:actions>
        </.admin_page_header>

        <section class="border-base-300/70 mb-8 flex flex-col gap-4 border-b pb-6 sm:mb-10 sm:flex-row sm:items-end sm:justify-between sm:gap-6 sm:pb-8">
          <div class="min-w-0">
            <p class="eyebrow text-base-content/65 mb-1">{~t"Total amount"}</p>
            <p class="text-base-content truncate text-3xl font-semibold tabular-nums tracking-tight sm:text-4xl">
              <span :if={@expense.total_amount && @expense.currency}>
                {Format.amount(@expense.total_amount, @expense.currency, @locale)}
              </span>
              <.blank :if={is_nil(@expense.total_amount) or is_nil(@expense.currency)} />
              <span :if={is_nil(@expense.total_amount) or is_nil(@expense.currency)} class="sr-only">
                {~t"No amount"}
              </span>
            </p>
          </div>
          <div class="sm:text-right">
            <p class="eyebrow text-base-content/65 mb-1.5">{~t"Confidence"}</p>
            <.confidence_badge confidence={@expense.confidence} />
          </div>
        </section>

        <section class="text-base-content/65 mb-10 flex flex-wrap items-center gap-x-2 gap-y-1 text-sm">
          <a
            href={Edenflowers.Papra.document_url(@expense.document_id)}
            target="_blank"
            rel="noopener"
            class="link link-primary -my-2 inline-flex items-center gap-1 py-2 font-medium"
          >
            {~t"Open receipt in Papra"}
            <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" />
          </a>
          <span :if={@expense.processed_at} class="max-sm:hidden" aria-hidden="true">·</span>
          <span :if={@expense.processed_at}>
            {~t"Processed"} {Format.datetime(@expense.processed_at, @locale)}
          </span>
          <span :if={@expense.reviewed_at} class="max-sm:hidden" aria-hidden="true">·</span>
          <span :if={@expense.reviewed_at}>
            {~t"Reviewed"} {Format.datetime(@expense.reviewed_at, @locale)}
          </span>
        </section>

        <section>
          <.form for={@form} id="expense-form" phx-submit="correct" phx-change="validate">
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <.input field={@form[:vendor_name]} type="text" label={~t"Vendor name"} class="input w-full" />
              <.input field={@form[:vendor_vat_number]} type="text" label={~t"VAT number"} class="input w-full" />
              <.input field={@form[:date]} type="date" label={~t"Date"} class="input w-full" />
              <.input
                field={@form[:currency]}
                type="select"
                label={~t"Currency"}
                options={[EUR: :eur, SEK: :sek]}
                class="select w-full"
              />
              <.input
                field={@form[:total_amount]}
                type="text"
                inputmode="decimal"
                label={~t"Total amount"}
                class="input w-full"
              />
              <.input
                field={@form[:vat_amount]}
                type="text"
                inputmode="decimal"
                label={~t"VAT amount"}
                class="input w-full"
              />
              <.input
                field={@form[:category]}
                type="select"
                label={~t"Category"}
                options={category_options()}
                class="select w-full"
              />
              <div class="sm:col-span-2">
                <.input field={@form[:description]} type="textarea" label={~t"Description"} class="textarea w-full" />
              </div>
            </div>
            <div class="mt-6 flex flex-col gap-3 sm:flex-row">
              <%!-- First in source order so Enter in a field saves without marking the expense reviewed. --%>
              <.button
                type="submit"
                variant={if is_nil(@expense.reviewed_at), do: "secondary", else: "primary"}
                class="w-full sm:w-auto"
              >
                {~t"Save corrections"}
              </.button>
              <.button
                :if={is_nil(@expense.reviewed_at)}
                type="submit"
                name="review"
                value="true"
                variant="primary"
                class="w-full sm:w-auto"
              >
                {~t"Save and mark reviewed"}
              </.button>
            </div>
          </.form>
        </section>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("correct", %{"form" => params} = submit_params, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, updated} when is_map_key(submit_params, "review") ->
        mark_reviewed(socket, updated)

      {:ok, updated} ->
        {:noreply,
         socket
         |> assign_expense(updated)
         |> put_flash(:info, ~t"Expense updated.")}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  defp mark_reviewed(socket, expense) do
    case Expenses.mark_expense_reviewed(expense, actor: socket.assigns.current_user) do
      {:ok, reviewed} ->
        {:noreply,
         socket
         |> assign_expense(reviewed)
         |> put_flash(:info, ~t"Expense saved and marked as reviewed.")}

      {:error, _} ->
        {:noreply,
         socket
         |> assign_expense(expense)
         |> put_flash(:error, ~t"Corrections saved, but the expense could not be marked as reviewed.")}
    end
  end

  defp assign_expense(socket, expense) do
    socket
    |> assign(:expense, expense)
    |> assign(:form, build_form(expense, socket.assigns.current_user))
  end

  defp build_form(expense, actor) do
    AshPhoenix.Form.for_update(expense, :correct, actor: actor) |> to_form()
  end
end
