local module = {}
local eps = 1e-9

local function isZero(d)
	return d > -eps and d < eps
end

local function cuberoot(x)
	return (x > 0) and math.pow(x, 1 / 3) or -math.pow(math.abs(x), 1 / 3)
end

local function clamp(x, a, b)
	return math.max(a, math.min(b, x))
end

local function horizontal(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function safeUnit(v)
	local m = v.Magnitude
	if m < eps then return Vector3.zero end
	return v / m
end

local function angleBetween(a, b)
	local ma = a.Magnitude
	local mb = b.Magnitude
	if ma < eps or mb < eps then return 0 end
	return math.acos(clamp(a:Dot(b) / (ma * mb), -1, 1))
end

local function solveQuadric(c0, c1, c2)
	local s0, s1
	local p, q, D

	p = c1 / (2 * c0)
	q = c2 / c0
	D = p * p - q

	if isZero(D) then
		s0 = -p
		return s0
	elseif D < 0 then
		return
	else
		local sqrt_D = math.sqrt(D)
		s0 = sqrt_D - p
		s1 = -sqrt_D - p
		return s0, s1
	end
end

local function solveCubic(c0, c1, c2, c3)
	local s0, s1, s2
	local num, sub
	local A, B, C
	local sq_A, p, q
	local cb_p, D

	A = c1 / c0
	B = c2 / c0
	C = c3 / c0

	sq_A = A * A
	p = (1 / 3) * (-(1 / 3) * sq_A + B)
	q = 0.5 * ((2 / 27) * A * sq_A - (1 / 3) * A * B + C)

	cb_p = p * p * p
	D = q * q + cb_p

	if isZero(D) then
		if isZero(q) then
			s0 = 0
			num = 1
		else
			local u = cuberoot(-q)
			s0 = 2 * u
			s1 = -u
			num = 2
		end
	elseif D < 0 then
		local phi = (1 / 3) * math.acos(-q / math.sqrt(-cb_p))
		local t = 2 * math.sqrt(-p)
		s0 = t * math.cos(phi)
		s1 = -t * math.cos(phi + math.pi / 3)
		s2 = -t * math.cos(phi - math.pi / 3)
		num = 3
	else
		local sqrt_D = math.sqrt(D)
		local u = cuberoot(sqrt_D - q)
		local v = -cuberoot(sqrt_D + q)
		s0 = u + v
		num = 1
	end

	sub = (1 / 3) * A

	if num > 0 then s0 = s0 - sub end
	if num > 1 then s1 = s1 - sub end
	if num > 2 then s2 = s2 - sub end

	return s0, s1, s2
end

function module.solveQuartic(c0, c1, c2, c3, c4)
	local s0, s1, s2, s3
	local coeffs = {}
	local z, u, v, sub
	local A, B, C, D
	local sq_A, p, q, r
	local num

	A = c1 / c0
	B = c2 / c0
	C = c3 / c0
	D = c4 / c0

	sq_A = A * A
	p = -0.375 * sq_A + B
	q = 0.125 * sq_A * A - 0.5 * A * B + C
	r = -(3 / 256) * sq_A * sq_A + 0.0625 * sq_A * B - 0.25 * A * C + D

	if isZero(r) then
		coeffs[3] = q
		coeffs[2] = p
		coeffs[1] = 0
		coeffs[0] = 1

		local results = {solveCubic(coeffs[0], coeffs[1], coeffs[2], coeffs[3])}
		num = #results
		s0, s1, s2 = results[1], results[2], results[3]
	else
		coeffs[3] = 0.5 * r * p - 0.125 * q * q
		coeffs[2] = -r
		coeffs[1] = -0.5 * p
		coeffs[0] = 1

		s0, s1, s2 = solveCubic(coeffs[0], coeffs[1], coeffs[2], coeffs[3])
		z = s0

		u = z * z - r
		v = 2 * z - p

		if isZero(u) then
			u = 0
		elseif u > 0 then
			u = math.sqrt(u)
		else
			return
		end

		if isZero(v) then
			v = 0
		elseif v > 0 then
			v = math.sqrt(v)
		else
			return
		end

		coeffs[2] = z - u
		coeffs[1] = q < 0 and -v or v
		coeffs[0] = 1

		do
			local results = {solveQuadric(coeffs[0], coeffs[1], coeffs[2])}
			num = #results
			s0, s1 = results[1], results[2]
		end

		coeffs[2] = z + u
		coeffs[1] = q < 0 and v or -v
		coeffs[0] = 1

		if num == 0 then
			local results = {solveQuadric(coeffs[0], coeffs[1], coeffs[2])}
			num = num + #results
			s0, s1 = results[1], results[2]
		end
		if num == 1 then
			local results = {solveQuadric(coeffs[0], coeffs[1], coeffs[2])}
			num = num + #results
			s1, s2 = results[1], results[2]
		end
		if num == 2 then
			local results = {solveQuadric(coeffs[0], coeffs[1], coeffs[2])}
			num = num + #results
			s2, s3 = results[1], results[2]
		end
	end

	sub = 0.25 * A

	if num > 0 then s0 = s0 - sub end
	if num > 1 then s1 = s1 - sub end
	if num > 2 then s2 = s2 - sub end
	if num > 3 then s3 = s3 - sub end

	return {s3, s2, s1, s0}
end

local function createHistory()
	return {samples = {}, maxSamples = 8}
end

function module.NewTracker(maxSamples)
	local tracker = createHistory()
	tracker.maxSamples = maxSamples or 8
	return tracker
end

function module.PushSample(tracker, pos, vel, t)
	if not tracker then return end
	local s = tracker.samples
	s[#s + 1] = {pos = pos, vel = vel or Vector3.zero, t = t or tick()}
	while #s > (tracker.maxSamples or 8) do
		table.remove(s, 1)
	end
end

local function estimateMotionFromHistory(tracker, fallbackVelocity, options)
	fallbackVelocity = fallbackVelocity or Vector3.zero
	options = options or {}

	if not tracker or not tracker.samples or #tracker.samples < 2 then
		return fallbackVelocity, Vector3.zero, {
			isJumping = false, isScaffolding = false,
			turnSharpness = 0, velocityWeight = 1, accelWeight = 1
		}
	end

	local s       = tracker.samples
	local newest  = s[#s]
	local prev    = s[#s - 1]
	local vel     = newest.vel or fallbackVelocity
	local accel   = Vector3.zero

	local meta = {
		isJumping = false, isScaffolding = false,
		turnSharpness = 0, velocityWeight = 1, accelWeight = 1
	}

	local dt         = math.max(newest.t - prev.t, 1 / 240)
	local derivedVel = (newest.pos - prev.pos) / dt

	if vel.Magnitude < 0.01 then
		vel = derivedVel
	else
		local blend = math.min(derivedVel.Magnitude / math.max(vel.Magnitude, eps), 1)
		vel = vel:Lerp(derivedVel, 0.45 * blend)
	end

	if #s >= 3 then
		local a  = s[#s - 2]
		local b  = s[#s - 1]
		local c  = s[#s]
		local dt1 = math.max(b.t - a.t, 1 / 240)
		local dt2 = math.max(c.t - b.t, 1 / 240)

		local v1 = (b.vel and b.vel.Magnitude > 0) and b.vel or ((b.pos - a.pos) / dt1)
		local v2 = (c.vel and c.vel.Magnitude > 0) and c.vel or ((c.pos - b.pos) / dt2)

		accel = (v2 - v1) / math.max((dt1 + dt2) * 0.5, 1 / 240)

		local flat1      = horizontal(v1)
		local flat2      = horizontal(v2)
		local turnAngle  = angleBetween(flat1, flat2)
		local speedDelta = flat2.Magnitude - flat1.Magnitude

		meta.turnSharpness = turnAngle

		if v2.Y > (options.jumpVyThreshold or 4) then
			meta.isJumping = true
		end

		if math.abs(c.pos.Y - b.pos.Y) > (options.scaffoldStepHeight or 1.4)
			and flat2.Magnitude < (options.scaffoldFlatSpeedMax or 5) then
			meta.isScaffolding = true
		end

		if math.abs(speedDelta) > (options.highAccelSpeedDelta or 2.5) then
			meta.accelWeight = 1.22
		end

		if turnAngle > (options.curveAngleThreshold or math.rad(10)) then
			meta.velocityWeight = 1.1
			meta.accelWeight    = meta.accelWeight + 0.18
		end

		if turnAngle > (options.sharpCurveAngleThreshold or math.rad(22)) then
			meta.velocityWeight = 1.18
			meta.accelWeight    = meta.accelWeight + 0.22
		end
	end

	if meta.isJumping then
		meta.velocityWeight = math.max(meta.velocityWeight, 1.08)
		accel = Vector3.new(accel.X, accel.Y * 1.12, accel.Z)
	end

	if meta.isScaffolding then
		vel   = Vector3.new(vel.X, math.max(vel.Y, options.scaffoldVerticalBoost or 6), vel.Z)
		accel = Vector3.new(accel.X, math.max(accel.Y, options.scaffoldAccelBoost or 2), accel.Z)
		meta.velocityWeight = math.max(meta.velocityWeight, 1.12)
		meta.accelWeight    = math.max(meta.accelWeight, 1.18)
	end

	return vel, accel, meta
end

function module.SolveTrajectory(origin, projectileSpeed, gravity, targetPos, targetVelocity, playerGravity, playerHeight, playerJump, params, options)
	options        = options or {}
	targetVelocity = targetVelocity or Vector3.zero

	local startTargetPos = targetPos

	local tracker               = options.tracker
	local latency               = options.latency or 0
	local shooterVelocity       = options.shooterVelocity or Vector3.zero
	local velocityWeight        = options.velocityWeight or 1
	local accelWeight           = options.accelWeight or 1
	local closeRange            = options.closeRange or 18
	local closeVelocityDamping  = options.closeVelocityDamping or 0.86
	local closeShooterComp      = options.closeShooterComp or 0.08
	local farRange              = options.farRange or 55
	local farStandingStill      = options.farStandingStillThreshold or 1.1
	local farShooterVelocityComp = options.farShooterVelocityComp or 1.08

	local targetAccel = Vector3.zero
	local motionVelocity, derivedAccel, motionMeta = estimateMotionFromHistory(tracker, targetVelocity, options)
	targetVelocity = motionVelocity * velocityWeight * (motionMeta.velocityWeight or 1)
	targetAccel    = derivedAccel  * accelWeight    * (motionMeta.accelWeight    or 1)

	if motionMeta.isJumping and playerGravity and playerGravity > 0 then
		local estT = math.min((targetPos - origin).Magnitude / math.max(projectileSpeed, 1), 2.0)
		local rawY = motionVelocity.Y
		local compensatedY = rawY - 0.5 * playerGravity * estT
		targetVelocity = Vector3.new(targetVelocity.X, compensatedY, targetVelocity.Z)
	end

	if latency ~= 0 then
		targetPos      = targetPos + targetVelocity * latency + 0.5 * targetAccel * latency * latency
		targetVelocity = targetVelocity + targetAccel * latency
	end

	local distance = (targetPos - origin).Magnitude
	local closeFactor = distance < closeRange and (1 - distance / closeRange) or 0

	if closeFactor > 0 then
		local relVel  = targetVelocity - shooterVelocity
		local flatRel = horizontal(relVel)
		local hScale = 1 - closeFactor * (1 - closeVelocityDamping)
		local yScale = motionMeta.isJumping
			and (1 - closeFactor * 0.25)
			or  (1 - closeFactor * 0.85)

		targetVelocity = Vector3.new(
			flatRel.X * hScale + shooterVelocity.X,
			targetVelocity.Y * yScale,
			flatRel.Z * hScale + shooterVelocity.Z
		)
		if latency > 0 then
			local nudge = horizontal(targetVelocity) * latency * (1 - closeFactor * 0.6)
			targetPos = targetPos + nudge
		end
	end

	if distance >= farRange and targetVelocity.Magnitude <= farStandingStill then
		targetPos = targetPos - shooterVelocity * latency * farShooterVelocityComp
	end
	if motionMeta.turnSharpness > math.rad(12) and closeFactor < 0.35 then
		local flatAccel = horizontal(targetAccel)
		if flatAccel.Magnitude > 0.01 then
			local curveLead = safeUnit(flatAccel) * math.min(
				flatAccel.Magnitude * (options.curveLeadScale or 0.045),
				options.curveLeadCap or 3.5
			)
			targetPos = targetPos + Vector3.new(curveLead.X, 0, curveLead.Z)
		end
	end

	if motionMeta.isScaffolding then
		targetPos = targetPos + Vector3.new(0, options.scaffoldExtraHeightLead or 0.35, 0)
	end

	local geoParams = options.geometryParams or params
	if geoParams then
		local ph       = playerHeight or 5
		local castFrom = startTargetPos + Vector3.new(0, ph * 0.5, 0)
		local castTo   = targetPos      + Vector3.new(0, ph * 0.5, 0)
		local castDir  = castTo - castFrom
		local castLen  = castDir.Magnitude

		if castLen > 0.5 then
			local geoRay = workspace:Raycast(castFrom, castDir, geoParams)
			if geoRay then
				local n = geoRay.Normal
				if n.Y > 0.4 then
					targetPos = Vector3.new(targetPos.X, geoRay.Position.Y + ph * 0.5, targetPos.Z)
				else
					local ratio = math.max(0, (geoRay.Distance - 0.3) / castLen)
					local clamped = castFrom + castDir * ratio - Vector3.new(0, ph * 0.5, 0)
					targetPos = Vector3.new(clamped.X, targetPos.Y, clamped.Z)
				end
			end
		end

		if targetPos.Y < startTargetPos.Y - 0.5 then
			local dropFrom = Vector3.new(targetPos.X, startTargetPos.Y + 1, targetPos.Z)
			local dropLen  = startTargetPos.Y - targetPos.Y + ph + 2
			local floorRay = workspace:Raycast(dropFrom, Vector3.new(0, -dropLen, 0), geoParams)
			if floorRay then
				targetPos = Vector3.new(targetPos.X, floorRay.Position.Y + ph, targetPos.Z)
			end
		end
	end

	local disp = targetPos - origin
	local p, q, r = targetVelocity.X, targetVelocity.Y, targetVelocity.Z
	local h, j, k = disp.X, disp.Y, disp.Z
	local l = -0.5 * gravity

	if math.abs(q) > 0.01 and playerGravity and playerGravity > 0 then
		local estTime = disp.Magnitude / projectileSpeed
		for _ = 1, 100 do
			q = q - (0.5 * playerGravity) * estTime
			local velo = targetVelocity * 0.016
			local ray  = workspace:Raycast(
				Vector3.new(targetPos.X, targetPos.Y, targetPos.Z),
				Vector3.new(velo.X, (q * estTime) - playerHeight, velo.Z),
				params
			)
			if ray then
				local newTarget = ray.Position + Vector3.new(0, playerHeight, 0)
				estTime   = estTime - math.sqrt(((targetPos - newTarget).Magnitude * 2) / playerGravity)
				targetPos = newTarget
				disp      = targetPos - origin
				h, j, k   = disp.X, disp.Y, disp.Z
				q = 0
				break
			else
				break
			end
		end
	end

	local solutions = module.solveQuartic(
		l * l,
		-2 * q * l,
		q * q - 2 * j * l - projectileSpeed * projectileSpeed + p * p + r * r,
		2 * j * q + 2 * h * p + 2 * k * r,
		j * j + h * h + k * k
	)

	if solutions then
		local posRoots = {}
		for _, v in ipairs(solutions) do
			if v and v > 0 then
				table.insert(posRoots, v)
			end
		end
		table.sort(posRoots)
		if posRoots[1] then
			local t = posRoots[1]
			local d = (h + p * t) / t
			local e = (j + q * t - l * t * t) / t
			local f = (k + r * t) / t
			return origin + Vector3.new(d, e, f), t, motionMeta
		end
	elseif gravity == 0 then
		local t = disp.Magnitude / projectileSpeed
		local d = (h + p * t) / t
		local e = (j + q * t - l * t * t) / t
		local f = (k + r * t) / t
		return origin + Vector3.new(d, e, f), t, motionMeta
	end
end

return module