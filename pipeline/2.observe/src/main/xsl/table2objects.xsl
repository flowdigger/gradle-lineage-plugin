<xsl:stylesheet version="3.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:xs="http://www.w3.org/2001/XMLSchema"
                xmlns:c="http://jurgenei.name/canonical"
                xmlns="http://jurgenei.name/canonical"
                expand-text="yes">
    <xsl:output method="xml" indent="yes" encoding="UTF-8"/>

    <xsl:template match="@*|*|processing-instruction()|comment()">
        <xsl:copy>
            <xsl:apply-templates select="*|@*|text()|processing-instruction()|comment()"/>
        </xsl:copy>
    </xsl:template>

    <xsl:template match="c:table">
        <application-components>
            <xsl:variable name="colNames" as="node()*">
                <xsl:apply-templates select="c:row[1]/c:cell/c:text" mode="strip"/>
            </xsl:variable>
<!--            <xsl:for-each select="$colNames">-->
<!--                <xsl:comment>{.}</xsl:comment>-->
<!--            </xsl:for-each>-->
            <xsl:apply-templates select="c:row[position() != 1]">
                <xsl:with-param name="colNames" select="$colNames" as="node()*"/>
            </xsl:apply-templates>
        </application-components>
    </xsl:template>

    <xsl:template match="c:text" mode="strip">
        <copy>{lower-case(replace(., '\s+', '-'))}</copy>
    </xsl:template>

    <xsl:template match="c:row">
        <xsl:param name="colNames" as="node()*"/>
        <xsl:variable name="row" select="."/>
        <application-component name="{replace(lower-case($row/c:cell[1]/c:text), '\s+', '-')}">
            <xsl:for-each select="$colNames[position() > 1]">
                <xsl:variable name="colIndex" select="position()"/>
                <xsl:variable name="colName" select="$colNames[$colIndex]"/>
                <xsl:variable name="colValue" select="normalize-space($row/c:cell[$colIndex])"/>
                <xsl:if test="string-length($colValue) > 0">
                    <xsl:element name="{$colName}">{$colValue}</xsl:element>
                </xsl:if>
            </xsl:for-each>
        </application-component>
    </xsl:template>
</xsl:stylesheet>