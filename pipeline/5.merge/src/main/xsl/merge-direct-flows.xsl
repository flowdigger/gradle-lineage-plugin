<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="3.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
    <xsl:output method="xml" indent="yes" encoding="utf-8"/>
    <xsl:strip-space elements="*"/>

    <xsl:template match="/direct-flows-catalog">
        <direct-flows-merged>
            <xsl:for-each-group select="direct-flow" group-by="@id">
                <xsl:sort select="current-grouping-key()"/>
                <xsl:variable name="sample" select="current-group()[1]"/>
                <direct-flow id="{$sample/@id}"
                             source="{$sample/@source}"
                             target="{$sample/@target}"
                             operation="{$sample/@operation}"
                             derivation-rule="{$sample/@derivation-rule}"
                             resolution-status="{$sample/@resolution-status}"
                             occurrences="{count(current-group())}">
                    <xsl:copy-of select="$sample/@*[name() = ('language','artifact','procedure')]"/>
                    <xsl:for-each-group select="current-group()/evidence/@ref" group-by="string(.)">
                        <xsl:sort select="current-grouping-key()"/>
                        <evidence ref="{current-grouping-key()}"/>
                    </xsl:for-each-group>
                </direct-flow>
            </xsl:for-each-group>
        </direct-flows-merged>
    </xsl:template>
</xsl:stylesheet>
