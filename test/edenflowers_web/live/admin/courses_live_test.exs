defmodule EdenflowersWeb.Admin.CoursesLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  use Oban.Testing, repo: Edenflowers.Repo

  import Phoenix.LiveViewTest
  import Generator

  alias AshAuthentication.Plug.Helpers

  setup %{conn: conn} do
    admin = generate(admin_user()) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(admin)

    %{conn: conn}
  end

  test "lists confirmed bookings with seat counts, hides unpaid ones and shows cancelled ones apart", %{conn: conn} do
    course = generate(course(name: "Autumn wreaths", total_places: 10))

    generate(course_registration(course_id: course.id, status: :confirmed, name: "Anna", email: "anna@example.com"))

    generate(course_registration(course_id: course.id, status: :pending, name: "Pending Pete"))
    generate(course_registration(course_id: course.id, status: :cancelled, name: "Cancelled Carl"))

    {:ok, view, html} = live(conn, ~p"/admin/courses")

    assert html =~ "Autumn wreaths"
    assert html =~ "1 / 10 places"
    assert has_element?(view, "li", "Anna")
    assert has_element?(view, ~s|a[href="https://app.fastmail.com/mail/compose?bcc=anna%40example.com"]|)
    refute html =~ "Pending Pete"
    assert has_element?(view, ".line-through", "Cancelled Carl")
  end

  test "cancelling a booking moves it to the cancelled list", %{conn: conn} do
    registration = generate(course_registration(status: :confirmed, name: "Anna"))

    {:ok, view, _html} = live(conn, ~p"/admin/courses")

    view |> element(~s|button[phx-click="cancel"][phx-value-id="#{registration.id}"]|) |> render_click()

    assert has_element?(view, ".line-through", "Anna")
    refute has_element?(view, ~s|button[phx-value-id="#{registration.id}"]|)
    assert Ash.get!(Edenflowers.Courses.CourseRegistration, registration.id, authorize?: false).status == :cancelled
  end

  test "adds a booking that pays at the course and emails a confirmation", %{conn: conn} do
    course = generate(course(name: "Autumn wreaths", total_places: 10))

    {:ok, view, _html} = live(conn, ~p"/admin/courses")

    view |> element(~s|button[phx-value-course-id="#{course.id}"]|) |> render_click()

    view
    |> form("#booking-form-#{course.id}",
      form: %{name: "Birgitta", email: "birgitta@example.com", locale: "sv-FI"}
    )
    |> render_submit()

    assert has_element?(view, "li", "Birgitta")
    assert has_element?(view, "li", "Pays at course")
    assert render(view) =~ "1 / 10 places"
    assert render(view) =~ "1 still to pay at the course"
    assert_enqueued(worker: Edenflowers.Courses.Workers.SendCourseConfirmationEmail)
  end

  test "marking a booking paid clears it from the still-to-pay list", %{conn: conn} do
    registration = generate(course_registration(status: :confirmed, name: "Birgitta"))

    {:ok, view, _html} = live(conn, ~p"/admin/courses")

    view |> element(~s|button[phx-click="mark_paid"][phx-value-id="#{registration.id}"]|) |> render_click()

    refute has_element?(view, "li", "Pays at course")
    refute render(view) =~ "still to pay"
  end

  test "links a Stripe booking to its payment in the Stripe dashboard", %{conn: conn} do
    generate(course_registration(status: :confirmed, payment_intent_id: "pi_123"))

    {:ok, view, _html} = live(conn, ~p"/admin/courses")

    assert has_element?(view, ~s|a[href$="/payments/pi_123"]|, "Stripe")
  end

  test "explains why a booking can't be added to a full course", %{conn: conn} do
    course = generate(course(total_places: 1))
    generate(course_registration(course_id: course.id, status: :confirmed))

    {:ok, view, _html} = live(conn, ~p"/admin/courses")

    view |> element(~s|button[phx-value-course-id="#{course.id}"]|) |> render_click()

    html =
      view
      |> form("#booking-form-#{course.id}", form: %{name: "Birgitta", email: "birgitta@example.com", locale: "sv-FI"})
      |> render_submit()

    assert html =~ "This course is fully booked."
  end
end
