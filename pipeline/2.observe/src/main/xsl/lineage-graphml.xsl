<xsl:stylesheet
                xmlns:l="urn:xmlast:lineage"
                xmlns:m="urn:git:metadata"
                xmlns:r="urn:xmlast:graph"
                expand-text="yes"
                version="3.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
    <xsl:output method="xml" indent="yes" encoding="UTF-8"/>

    <xsl:template match="/*">
        <xsl:copy>
            <xsl:copy-of select="@*"/>
            <xsl:apply-templates/>
        </xsl:copy>
    </xsl:template>

    <xsl:template match="r:from">
        <a from="{@name}" to="{ancestor::r:to/@name}" procedure="{ancestor::procedure/@name}"/>
    </xsl:template>

<!--    <xsl:template match="@*|*|processing-instruction()|comment()">-->
<!--        <xsl:copy>-->
<!--            <xsl:apply-templates select="*|@*|text()|processing-instruction()|comment()"/>-->
<!--        </xsl:copy>-->
<!--    </xsl:template>-->

    <xsl:template match="text()"/>
</xsl:stylesheet>