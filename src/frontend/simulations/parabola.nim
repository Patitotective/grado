import std/[math, jsffi, dom, jsconsole, enumerate, with, strformat]
import karax/[karax, karaxdsl, vdom, vstyles]

import matter, utils

type
  Exercise = object
    pos: tuple[x, y: int]
    angle: float
    speed: int

  ExerciseStatus = enum
    esStart # Not launched yet
    esStarted # In the air
    esEnd # Touched something and stopped

const
  deltaTime = 16.666
  canvasWidth = 700
  canvasHeight = 500
  floorHeight = 20

let
  wrapObject = JsObject{min: JsObject{x: 0, y: undefined}, max: JsObject{x: canvasWidth, y: undefined}} # To avoid boilerplate

var
  engine*, mrender*, bullet, floor, ground*, runner*: JsObject
  constraint*, mconstraint*, mouse*: JsObject
  canvas*: Element

  trail = newSeq[JsVector]()
  mConstraintDragEnded*: bool # True when you release the mouse constraint

  exercises = @[Exercise(pos: (50, 0), angle: 300, speed: 12)]
  currentExercise = -1
  exerciseStatus: ExerciseStatus
  finalSpeed: int # Final speed of an exercise

## Loads the simulation
proc load*() =
  # Render all MathJax expressions asynchronously
  MathJax.typesetPromise()

  # Load wrap's plugin and load matter aliases to point to the correct values
  Matter.use("matter-wrap")
  loadMatterAliases()

  canvas = getElementById("canvas")
  engine = Engine.create()
  mrender = Render.create(JsObject{
    canvas: canvas,
    engine: engine,
    options: JsObject{
      width: canvasWidth,
      height: canvasHeight,
      showAngleIndicator: true,
      background: "rgb(20, 21, 31)",
    }
  })
  Render.run(mrender)

  runner = Runner.create(JsObject{delta: deltaTime})
  Runner.run(runner, engine)

  # Create and add all bodies to the world
  bullet = Bodies.circle(500, 300, 25, JsObject{isStatic: false, frictionAir: 0, friction: 1, mass: 2, plugin: JsObject{wrap: wrapObject}})

  Body.setInertia(bullet, Infinity)
  # Body.setAngle(bullet, degToRad(180d))

  # constraint = Constraint.create(JsObject{pointA: JsObject{x: 400, y: 300}, bodyB: bullet, length: 30, stiffness: 0.1})

  floor = Bodies.rectangle(350, 495, 1200, floorHeight, JsObject{isStatic: true})

  mouse = Mouse.create(canvas)
  mconstraint = MouseConstraint.create(engine, JsObject{mouse: mouse})

  Composite.add(engine.world, toJs [bullet, mconstraint,
    # Walls
    Bodies.rectangle(350, -200, 1000, 20, JsObject{isStatic: true}), # up
    # Bodies.rectangle(690, 250, 20, 500, JsObject{isStatic: true}), # right
    floor, # down
    # Bodies.rectangle(10, 250, 20, 500, JsObject{isStatic: true}), # left
    # Thingy
    Bodies.rectangle(400, 350, 20, 80, JsObject{isStatic: false, plugin: JsObject{wrap: wrapObject}})

  ])

  # Set event callbacks
  Events.on(engine, "afterUpdate", proc() =
    # So that it updates the formula values
    if not kxi.surpressRedraws: redraw(kxi)
  )

  Events.on(mrender, "afterRender", proc() =
    Render.startViewTransform(mrender)
    mrender.context.globalAlpha = 0.7

    for i in trail:
      mrender.context.fillStyle = cstring"orange"
      mrender.context.fillRect(JsObject(i).x, JsObject(i).y, 2, 2)

    mrender.context.globalAlpha = 1
    Render.endViewTransform(mrender)
  )

## Reloads the simulation
proc reload() =
  Composite.clear(engine.world)
  Engine.clear(engine)
  Render.stop(mrender)
  Runner.stop(runner)
  trail.setLen(0)
  load()

## Since a body's angle can be negative and can be higher than 360, this procedure makes it so it's always positive and inside 0..359
proc normalizeAngle(rad: float): int =
  result = int rad.radToDeg()
  result -= (result div 360) * 360 # Remove excess rotations
  if result < 0:
    result = abs result
  elif result > 0:
    result = 360 - result

## Since matter measures y since the top of the screen, here we "normalize" it so that the 0 starts at the floor
proc normalizeY(y: int): int =
  -y + (floor.position.y.to(int) - (floorHeight div 2) - bullet.circleRadius.to(int))

proc sendBulletFlying() =
  # let speed = bullet.circleRadius.to(float64) * 0.48 # force magnitude
  let speed = float64 exercises[currentExercise].speed
  let x = cos(bullet.angle.to(float64)) * speed
  let y = sin(bullet.angle.to(float64)) * speed

  Body.setVelocity(bullet, JsObject{x: x, y: y})

proc rotateBullet(clockwise = true) =
  var rad = degToRad(20d)#(360 / bullet.vertices.length.to(float64))*2)
  if not clockwise:
    rad = -rad

  Body.rotate(bullet, rad)

proc calcTrajectory() =
  var stop = false # Stop updating the engine
  # let bodies = cloneAllBodies(engine.world)
  let oldb = bullet.structuredClone()
  # print bullet.jsonStringify()

  var formerStaticBodies: seq[JsObject]
  for body in Composite.allBodies(engine.world):
    if body.id != bullet.id:
      if body.isStatic.to(bool) == true:
        formerStaticBodies.add body.id
      else:
        Body.setStatic(body, true)

  proc onCollision(event: JsObject) =
    if event.pairs[0].bodyA.id == bullet.id:
      stop = true

  Events.on(engine, "collisionStart", onCollision)

  sendBulletFlying()

  trail.setLen(0)
  for i in 1..1000:
    echo i
    print bullet.velocity
    if stop:
      exerciseStatus = esEnd
      break

    finalSpeed = int bullet.speed.to(float)
    trail.add JsVector JsObject{x: jsFloatToInt bullet.position.x, y: jsFloatToInt bullet.position.y}

    Engine.update(engine)

  Events.off(engine, "collitionStart", onCollision)

  for b in [bullet]:#enumerate Composite.allBodies(engine.world):
    # assert b.id == bodies[e].id
    # let oldb = bodies[e]
    # Object.assign(b, oldb)

    b.force = oldb.force
    b.torque = oldb.torque
    b.positionImpulse = oldb.positionImpulse
    b.constraintImpulse = oldb.constraintImpulse
    b.positionPrev = oldb.positionPrev
    # Body.setParts(b, oldb.parts)# b.parts = oldb.parts
    # Body.setVertices(b, oldb.vertices)# b.vertices = oldb.vertices
    # b.bounds = oldb.bounds

    Body.setPosition(b, oldb.position)
    Body.setAngle(b, oldb.angle)
    Body.setVelocity(b, oldb.velocity)
    Body.setAngularVelocity(b, oldb.angularVelocity)

  for body in Composite.allBodies(engine.world):
    if body.id != bullet.id and body.id notin formerStaticBodies:
      Body.setStatic(body, false)

  # print bullet.jsonStringify()#Composite.allBodies(engine.world).jsonStringify()

proc renderTextDiv*(): VNode =
  buildHtml tdiv(style = "float: left; width: 40%;".toCss):
    p(text r"\(a = \frac{v_f - v_i}{\Delta t}\)", style = "font-size: 80px;".toCss)

    if not bullet.isNil:
      p(text &"x = {int bullet.position.x.to(float)} y = {normalizeY(int bullet.position.y.to(float))}")
      p(text &"angle = {normalizeAngle(bullet.angle.to(float))}")

      if currentExercise > -1:
        let exercise = exercises[currentExercise]
        p(text &"Vi = {exercise.speed}")
        # if exerciseStatus == esEnd:
        p(text &"Vf = {finalSpeed}")
        # else:
          # p(text &"Vf = ?")

    # p(text fmt"\(a = \frac{{v_f - {bullet.position.x}}}{{\Delta t}}\)", style = "font-size: 80px;".toCss)

proc renderSimDiv*(): VNode =
  proc exerciseOnClick(current: int): proc =
    proc () =
      let exercise = exercises[current]
      currentExercise = current
      Body.setPosition(bullet, JsObject{x: exercise.pos.x, y: normalizeY(exercise.pos.y)})
      Body.setAngle(bullet, degToRad(exercise.angle))
      calcTrajectory()
      exerciseStatus = esStart

  buildHtml tdiv(style = "float: right; width: 40%;".toCss):
    button():
      text "Start the simulation"
      proc onclick()  =
          engine.timing.timeScale = 1

    button():
      text "Stop the simulation"
      proc onclick() =
        engine.timing.timeScale = 0

    button():
      text "Rotate"
      proc onclick() =
        rotateBullet()

    button(onclick = calcTrajectory):
      text "Trajectory"

    button():
      text "Rot & Traj"
      proc onclick() =
        rotateBullet()
        calcTrajectory()

    button():
      text "Send ball flying"
      proc onclick() =
        sendBulletFlying()

    canvas(id = "canvas", style = fmt"width: {canvasWidth}px; height: {canvasHeight}px; background: rgb(20, 21, 31)".toCss):
      text "Matter-js simulation"

    tdiv(id = "exercises", style = "height: 200px; overflow-y: auto;".toCss):
      for e, exercise in exercises:
        button(onclick = exerciseOnClick(e)):
          text &"#{e+1} {exercise}"

proc render*(): VNode =
  buildHtml tdiv(style = "width: 100%; justify-content: center; align-items: center;".toCss):
    renderTextDiv()
    renderSimDiv()

document.addEventListener("keyup", proc (event: Event) =
  let event = KeyboardEvent(event)
  case $event.key
  of "t":
    calcTrajectory()
  of "ArrowRight":
    rotateBullet()
    calcTrajectory()
  of "ArrowLeft":
    rotateBullet(false)
    calcTrajectory()
  of "ArrowUp":
    sendBulletFlying()
  of "Backspace":
    reload()
  of "p":
    if engine.timing.timeScale.to(int) == 0:
      engine.timing.timeScale = 1
    else:
      engine.timing.timeScale = 0
  of "d":
    jsonPrint bullet
)


