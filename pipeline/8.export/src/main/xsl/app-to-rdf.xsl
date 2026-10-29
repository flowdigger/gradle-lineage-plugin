<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="3.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:r="urn:xmlast:graph"
                xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                xmlns:lin="urn:uniform-lineage"
                exclude-result-prefixes="r lin">
    <xsl:output method="xml" indent="yes" encoding="utf-8"/>
    <xsl:strip-space elements="*"/>

    <xsl:template match="/applicationcomponent">
        <xsl:variable name="processor" select="string(@name)"/>
        <rdf:RDF>
            <xsl:for-each select="database">
                <xsl:variable name="db" select="string(@name)"/>
                <xsl:for-each select="procedures/procedure">
                    <xsl:variable name="proc" select="string(@name)"/>
                    <xsl:for-each select="r:graph/r:to">
                        <xsl:variable name="to" select="string(@name)"/>
                        <xsl:for-each select="r:from">
                            <xsl:variable name="from" select="string(@name)"/>
                            <rdf:Description rdf:about="{concat('urn:lineage:app-flow:', generate-id(.))}">
                                <lin:processor><xsl:value-of select="$processor"/></lin:processor>
                                <lin:database><xsl:value-of select="$db"/></lin:database>
                                <lin:procedure><xsl:value-of select="$proc"/></lin:procedure>
                                <lin:source><xsl:value-of select="$from"/></lin:source>
                                <lin:target><xsl:value-of select="$to"/></lin:target>
                            </rdf:Description>
                        </xsl:for-each>
                    </xsl:for-each>
                </xsl:for-each>
            </xsl:for-each>
        </rdf:RDF>
    </xsl:template>
</xsl:stylesheet>
