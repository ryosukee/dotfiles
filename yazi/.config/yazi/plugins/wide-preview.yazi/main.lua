--- @since 26.1.22
--- @sync entry

-- preview カラムの幅を 2 つの比率で往復させる。
-- 比率は [親, 一覧, preview] で、NARROW は yazi 側の preset と同じ値。
-- yazi.toml の [mgr] ratio を設定したら、NARROW をその値に合わせる。
-- rt.mgr.ratio は読むと parent / current / preview / all の table を返すが、
-- 書くときは 3 要素の配列しか受け付けない。
-- 書き換えだけではレイアウトが再計算されないので、app:resize を emit する。

local NARROW = { 1, 4, 3 }
local WIDE = { 1, 2, 5 }

local function entry()
	if rt.mgr.ratio.preview == WIDE[3] then
		rt.mgr.ratio = NARROW
	else
		rt.mgr.ratio = WIDE
	end

	ya.emit("app:resize", {})
end

return { entry = entry }
