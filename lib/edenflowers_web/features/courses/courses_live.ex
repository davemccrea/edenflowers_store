defmodule EdenflowersWeb.Courses.CoursesLive do
  use EdenflowersWeb, :live_view

  alias Edenflowers.Courses
  alias Edenflowers.Format
  alias Edenflowers.Translations

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    courses =
      [load: [:seats_left, :booking_open?], query: [sort: [date: :asc, start_time: :asc]]]
      |> Courses.list_upcoming_courses!()
      |> Translations.translate()

    {:ok, assign(socket, page_title: ~t"Courses", locale: Format.locale(), courses: courses)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <section class="flex flex-col gap-12 md:flex-row md:items-center md:gap-16 lg:gap-24">
          <div class="flex max-w-2xl flex-col gap-6">
            <h1 class="page-title mb-4">{~t"Courses"}</h1>
            <p class="text-base-content/80 text-lg leading-relaxed">
              {~t"Join me for a few hours of hands-on floristry. I bring the flowers and show you how, and you take home what you make."}
            </p>
            <div class="mt-2">
              <.button href="#coming-up" variant="primary">{~t"See upcoming courses"}</.button>
            </div>
          </div>
          <%!-- Hidden on phones so the dates, which are what people came for, sit above the fold. --%>
          <div class="hidden flex-shrink-0 md:block md:w-80 lg:w-96">
            <.image
              src="local:///image_1.jpg"
              alt=""
              width={800}
              height={1000}
              sizes="(min-width: 1024px) 24rem, 20rem"
              class="aspect-[4/5] w-full object-cover"
            />
          </div>
        </section>

        <section
          id="coming-up"
          class="border-base-content/12 scroll-anchor-below-header mt-14 border-t pt-10 sm:mt-20 sm:pt-14"
          aria-labelledby="upcoming-heading"
        >
          <div class="max-w-2xl">
            <h2 id="upcoming-heading" class="section-title">{~t"Coming up"}</h2>

            <div :if={@courses == []} class="mt-6" data-testid="no-courses">
              <p class="text-base-content/80 max-w-prose">
                {~t"There are no courses on the calendar right now. I announce new dates in the newsletter first."}
              </p>
              <.button href="#newsletter" variant="text" class="mt-4">{~t"Sign up for the newsletter"}</.button>
            </div>

            <ol :if={@courses != []} class="mt-8" data-testid="courses-list">
              <li :for={course <- @courses} class="border-base-content/12 border-t first:border-t-0">
                <.course_row course={course} locale={@locale} />
              </li>
            </ol>
          </div>
        </section>
      </.container>
    </Layouts.app>
    """
  end

  attr :course, :map, required: true
  attr :locale, :any, required: true

  # A full or closed course keeps its row: it still tells people courses happen.
  defp course_row(assigns) do
    ~H"""
    <div class="grid-cols-[5rem_1fr] grid items-baseline gap-x-4 gap-y-2 py-6 sm:grid-cols-[8rem_1fr_auto] sm:gap-x-8">
      <p class="text-base-content/70 tabular-nums">{Format.day_month(@course.date, @locale)}</p>

      <div>
        <h3 class="card-title text-balance">
          <.link :if={@course.booking_open?} navigate={~p"/courses/#{@course.id}"} class="link-underline-hover">
            {@course.name}
          </.link>
          <span :if={!@course.booking_open?} class="text-base-content/70">{@course.name}</span>
        </h3>
        <p class="text-base-content/70 mt-1 text-sm tabular-nums">
          {Format.time(@course.start_time, @locale)}–{Format.time(@course.end_time, @locale)} · {@course.location_name}
        </p>
      </div>

      <div class="col-start-2 sm:col-start-3 sm:row-start-1 sm:text-right">
        <p class="text-base-content font-serif text-xl tabular-nums">{Format.price(@course.price, @locale)}</p>
        <p class="text-base-content/70 text-sm">{availability(@course)}</p>
      </div>
    </div>
    """
  end

  defp availability(%{seats_left: seats_left}) when seats_left <= 0, do: ~t"Fully booked"
  defp availability(%{booking_open?: false}), do: ~t"Booking closed"
  defp availability(%{seats_left: seats_left}), do: ~t"#{count = seats_left} place(s) left"N
end
