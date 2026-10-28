local ReaderFooter = require("apps/reader/modules/readerfooter")

local orig_getHeight = ReaderFooter.getHeight

function ReaderFooter:getHeight()
    -- 状态栏关闭时，不预留任何高度
    if not self.view or not self.view.footer_visible then
        return 0
    end
    return orig_getHeight(self)
end

-- 绕过界面里"最小 7"的限制：启动时直接把已保存的值改成 0
local orig_init = ReaderFooter.init
function ReaderFooter:init(...)
    orig_init(self, ...)
    if self.settings then
        self.settings.container_height = 0
        self.settings.container_bottom_padding = 0
    end
    if self.updateFooterContainer then
        self:updateFooterContainer()
    end
end