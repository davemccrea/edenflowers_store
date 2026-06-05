defmodule EdenflowersWeb.Admin.ExpenseDetailLive do
  use EdenflowersWeb, :live_view

  alias EdenflowersWeb.Layouts
  alias Edenflowers.Expenses.Expense

  on_mount {EdenflowersWeb.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    expense = Ash.get!(Expense, id, actor: socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Expense — #{expense.vendor_name || id}")
     |> assign(:expense, expense)
     |> assign(:form, build_form(expense, socket.assigns.current_user))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path}>
      <div class="container mx-auto py-10 max-w-2xl">
        <div class="mb-8">
          <.link navigate={~p"/admin/expenses"} class="text-sm text-base-content/55 hover:text-base-content/80">
            ← Back to Expenses
          </.link>
        </div>

        <header class="mb-8">
          <p class="eyebrow text-base-content/55 mb-2">Expense</p>
          <h1 class="page-title">{@expense.vendor_name || "Unknown vendor"}</h1>
        </header>

        <section class="mb-10 grid grid-cols-2 gap-4 text-sm">
          <div>
            <dt class="text-xs text-base-content/55 uppercase tracking-wide mb-0.5">Document</dt>
            <dd>
              <a
                href={Edenflowers.Papra.document_url(@expense.document_id)}
                target="_blank"
                rel="noopener"
                class="link link-primary text-sm"
              >
                {@expense.document_id}
              </a>
            </dd>
          </div>
          <.detail_row label="Date" value={@expense.date} />
          <.detail_row label="Total Amount" value={"#{@expense.total_amount} #{@expense.currency}"} />
          <.detail_row label="VAT Amount" value={@expense.vat_amount} />
          <.detail_row label="VAT Number" value={@expense.vendor_vat_number} />
          <.detail_row label="Category" value={@expense.category} />
          <.detail_row label="Confidence" value={@expense.confidence} />
          <.detail_row label="Processed" value={@expense.processed_at} />
          <.detail_row label="Reviewed" value={if @expense.reviewed_at, do: @expense.reviewed_at, else: "Not reviewed"} />
          <div class="col-span-2">
            <.detail_row label="Description" value={@expense.description} />
          </div>
        </section>

        <section class="mb-10">
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-base font-semibold">Mark as Reviewed</h2>
          </div>
          <button
            :if={is_nil(@expense.reviewed_at)}
            type="button"
            phx-click="mark_reviewed"
            class="btn btn-primary btn-sm"
          >
            Mark as Reviewed
          </button>
          <p :if={not is_nil(@expense.reviewed_at)} class="text-sm text-base-content/55">
            Reviewed at {Calendar.strftime(@expense.reviewed_at, "%Y-%m-%d %H:%M UTC")}
          </p>
        </section>

        <section>
          <h2 class="text-base font-semibold mb-4">Correct Extracted Data</h2>
          <.form for={@form} phx-submit="correct" phx-change="validate">
            <div class="grid grid-cols-2 gap-4">
              <div class="form-control">
                <label class="label"><span class="label-text">Vendor Name</span></label>
                <.input field={@form[:vendor_name]} type="text" class="input input-bordered input-sm w-full" />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">VAT Number</span></label>
                <.input field={@form[:vendor_vat_number]} type="text" class="input input-bordered input-sm w-full" />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Date</span></label>
                <.input field={@form[:date]} type="date" class="input input-bordered input-sm w-full" />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Currency</span></label>
                <.input field={@form[:currency]} type="select" options={["EUR": :eur, "SEK": :sek]} class="select select-bordered select-sm w-full" />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Total Amount</span></label>
                <.input field={@form[:total_amount]} type="text" class="input input-bordered input-sm w-full" />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">VAT Amount</span></label>
                <.input field={@form[:vat_amount]} type="text" class="input input-bordered input-sm w-full" />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text">Category</span></label>
                <.input
                  field={@form[:category]}
                  type="select"
                  options={[
                    "Office Supplies": :office_supplies,
                    "Travel": :travel,
                    "Meals": :meals,
                    "Software": :software,
                    "Marketing": :marketing,
                    "Utilities": :utilities,
                    "Professional Services": :professional_services,
                    "Other": :other
                  ]}
                  class="select select-bordered select-sm w-full"
                />
              </div>
              <div class="form-control col-span-2">
                <label class="label"><span class="label-text">Description</span></label>
                <.input field={@form[:description]} type="textarea" class="textarea textarea-bordered textarea-sm w-full" />
              </div>
            </div>
            <div class="mt-6">
              <button type="submit" class="btn btn-primary btn-sm">Save Corrections</button>
            </div>
          </.form>
        </section>
      </div>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("mark_reviewed", _params, socket) do
    case Expense.mark_reviewed(socket.assigns.expense, actor: socket.assigns.current_user) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:expense, updated)
         |> put_flash(:info, "Expense marked as reviewed.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not mark expense as reviewed.")}
    end
  end

  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("correct", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:expense, updated)
         |> assign(:form, build_form(updated, socket.assigns.current_user))
         |> put_flash(:info, "Expense updated.")}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  defp build_form(expense, actor) do
    AshPhoenix.Form.for_update(expense, :correct, actor: actor) |> to_form()
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp detail_row(assigns) do
    ~H"""
    <div>
      <dt class="text-xs text-base-content/55 uppercase tracking-wide mb-0.5">{@label}</dt>
      <dd class="text-base-content">{@value || "—"}</dd>
    </div>
    """
  end
end
